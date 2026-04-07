use crate::error::{GteError, Result};
use crate::model_config::{ExtractorMode, ModelConfig};
use crate::tokenizer::Tokenized;
use ndarray::{Array2, Ix2};
use ort::session::Session;
use ort::value::Value;
use std::collections::HashMap;
use std::path::Path;

/// Create an ORT inference session from a local ONNX model file.
///
/// Applies graph optimization level, thread configuration, and memory pattern
/// optimization for best inference performance.
pub fn build_session<P: AsRef<Path>>(model_path: P, config: &ModelConfig) -> Result<Session> {
    let opt_level = match config.optimization_level {
        0 => ort::session::builder::GraphOptimizationLevel::Disable,
        1 => ort::session::builder::GraphOptimizationLevel::Level1,
        2 => ort::session::builder::GraphOptimizationLevel::Level2,
        _ => ort::session::builder::GraphOptimizationLevel::Level3,
    };

    let mut builder = Session::builder()?
        .with_optimization_level(opt_level)?
        .with_memory_pattern(true)?;

    if config.num_threads > 0 {
        builder = builder.with_intra_threads(config.num_threads)?;
    }

    let session = builder.commit_from_file(model_path)?;
    Ok(session)
}

/// Run the ORT session on tokenized inputs and extract embeddings as Array2<f32>.
///
/// CRITICAL: `SessionOutputs` borrows from `Session`. This function extracts the owned
/// `Array2<f32>` before returning — never return `SessionOutputs` from here (Pitfall 1).
///
/// All input tensors are `i64` (token IDs, attention masks, type IDs). The HashMap is
/// typed to `Value<TensorValueType<i64>>` — do not mix tensor types in the same map (Pitfall 3).
pub fn run_session(
    session: &Session,
    tokenized: &Tokenized,
    config: &ModelConfig,
) -> Result<Array2<f32>> {
    // Build typed input HashMap — all inputs are i64 tensors (Pitfall 3)
    let mut inputs: HashMap<&str, Value<ort::value::TensorValueType<i64>>> = HashMap::new();
    inputs.insert("input_ids", Value::from_array(tokenized.input_ids.view())?);
    if config.with_attention_mask {
        inputs.insert(
            "attention_mask",
            Value::from_array(tokenized.attn_masks.view())?,
        );
    }
    if let Some(ref type_ids) = tokenized.type_ids {
        inputs.insert("token_type_ids", Value::from_array(type_ids.view())?);
    }

    let outputs = session.run(inputs)?;

    // Extract the embedding tensor by name from session outputs
    let tensor_value = outputs.get(config.output_tensor.as_str()).ok_or_else(|| {
        GteError::Inference(format!(
            "output tensor '{}' not found in model outputs",
            &config.output_tensor
        ))
    })?;

    let array = tensor_value.try_extract_tensor::<f32>()?;

    // Apply extraction mode based on model config
    let embeddings: Array2<f32> = match config.mode {
        ExtractorMode::Token(idx) => {
            // Shape: [batch, seq, dim] — take token at idx (usually 0 = CLS)
            let shape = array.shape();
            if shape.len() != 3 || idx >= shape[1] {
                return Err(GteError::Inference(format!(
                    "token extraction index {} out of bounds for output shape {:?}",
                    idx, shape
                )));
            }
            let slice = array.slice(ndarray::s![.., idx, ..]);
            slice.into_owned()
        }
        ExtractorMode::MeanPool => {
            // Shape: [batch, seq, dim] — mean pool using attention mask
            let shape = array.shape();
            if shape.len() != 3 {
                return Err(GteError::Inference(format!(
                    "mean pooling requires rank-3 output, got shape {:?}",
                    shape
                )));
            }
            let (batch, seq, dim) = (shape[0], shape[1], shape[2]);
            let mask = &tokenized.attn_masks; // [batch, seq] i64
            let mut result = Array2::<f32>::zeros((batch, dim));
            // Fast path for contiguous arrays, fallback to indexed path otherwise.
            if let (Some(array_slice), Some(mask_slice), Some(result_slice)) = (
                array.as_slice_memory_order(),
                mask.as_slice_memory_order(),
                result.as_slice_memory_order_mut(),
            ) {
                for b in 0..batch {
                    let mask_base = b * seq;
                    let hidden_base = b * seq * dim;
                    let mut sum_mask: f32 = 0.0;
                    let result_row = &mut result_slice[b * dim..(b + 1) * dim];
                    for s in 0..seq {
                        let m = mask_slice[mask_base + s];
                        if m > 0 {
                            let mf = m as f32;
                            let tok_base = hidden_base + s * dim;
                            for d in 0..dim {
                                result_row[d] += array_slice[tok_base + d] * mf;
                            }
                            sum_mask += mf;
                        }
                    }
                    if sum_mask > 0.0 {
                        let inv = 1.0 / sum_mask;
                        for d in 0..dim {
                            result_row[d] *= inv;
                        }
                    }
                }
            } else {
                for b in 0..batch {
                    let mut sum_mask: f32 = 0.0;
                    for s in 0..seq {
                        let m = mask[[b, s]];
                        if m > 0 {
                            let mf = m as f32;
                            for d in 0..dim {
                                result[[b, d]] += array[[b, s, d]] * mf;
                            }
                            sum_mask += mf;
                        }
                    }
                    if sum_mask > 0.0 {
                        let inv = 1.0 / sum_mask;
                        for d in 0..dim {
                            result[[b, d]] *= inv;
                        }
                    }
                }
            }
            result
        }
        ExtractorMode::Raw => {
            // Shape: [batch, dim] — already pooled
            array.into_dimensionality::<Ix2>()?.into_owned()
        }
    };

    Ok(embeddings)
}
