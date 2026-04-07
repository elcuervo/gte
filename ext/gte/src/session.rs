use std::collections::HashMap;
use std::path::Path;
use ndarray::{Array2, Ix2};
use ort::session::Session;
use ort::value::Value;
use crate::error::{GteError, Result};
use crate::model_config::{ExtractorMode, ModelConfig};
use crate::tokenizer::Tokenized;

/// Create an ORT inference session from a local ONNX model file.
///
/// Uses ORT v2 API: `Session::builder()?.commit_from_file(path)`
/// NOT the v1 `SessionBuilder::new()` API (does not exist in ort 2.0.0-rc.9).
pub fn build_session<P: AsRef<Path>>(model_path: P) -> Result<Session> {
    let session = Session::builder()?.commit_from_file(model_path)?;
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
    inputs.insert(
        "attention_mask",
        Value::from_array(tokenized.attn_masks.view())?,
    );
    if let Some(ref type_ids) = tokenized.type_ids {
        inputs.insert("token_type_ids", Value::from_array(type_ids.view())?);
    }

    let outputs = session.run(inputs)?;

    // Extract the embedding tensor by name from session outputs
    let tensor_value = outputs.get(config.output_tensor).ok_or_else(|| {
        GteError::Inference(format!(
            "output tensor '{}' not found in model outputs",
            config.output_tensor
        ))
    })?;

    let array = tensor_value.try_extract_tensor::<f32>()?;

    // Apply extraction mode: CLS token (rank-3 → rank-2) or Raw (rank-2 already)
    // Pitfall 5: Token(idx) requires rank-3 output; E5's last_hidden_state is confirmed rank-3
    let embeddings: Array2<f32> = match config.mode {
        ExtractorMode::Token(idx) => {
            // Shape: [batch, seq, dim] — take token at idx (usually 0 = CLS)
            let slice = array.slice(ndarray::s![.., idx, ..]);
            slice.into_owned()
        }
        ExtractorMode::Raw => {
            // Shape: [batch, dim] — already pooled
            array.into_dimensionality::<Ix2>()?.into_owned()
        }
    };

    Ok(embeddings)
}
