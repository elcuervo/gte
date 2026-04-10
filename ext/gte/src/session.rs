use crate::error::{GteError, Result};
use crate::model_config::{ExtractorMode, ModelConfig};
use crate::postprocess::mean_pool;
use crate::tokenizer::Tokenized;
use ndarray::{Array2, ArrayView2, Ix2};
use ort::execution_providers::{
    CoreMLExecutionProvider, ExecutionProviderDispatch, XNNPACKExecutionProvider,
};
use ort::session::Session;
use ort::session::SessionInputValue;
use ort::value::Value;
use std::path::Path;

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

    let providers = preferred_execution_providers();
    if !providers.is_empty() {
        builder = builder.with_execution_providers(providers)?;
    }

    if config.num_threads > 0 {
        builder = builder.with_intra_threads(config.num_threads)?;
    }

    Ok(builder.commit_from_file(model_path)?)
}

fn preferred_execution_providers() -> Vec<ExecutionProviderDispatch> {
    let order = std::env::var("GTE_EXECUTION_PROVIDERS")
        .unwrap_or_else(|_| "xnnpack".to_string())
        .to_ascii_lowercase();

    let mut providers = Vec::new();
    for provider in order.split(',').map(str::trim).filter(|p| !p.is_empty()) {
        match provider {
            "xnnpack" => providers.push(XNNPACKExecutionProvider::default().build().fail_silently()),
            "coreml" => providers.push(CoreMLExecutionProvider::default().build().fail_silently()),
            "none" => {}
            _ => {}
        }
    }
    providers
}

pub fn run_session(
    session: &Session,
    tokenized: &Tokenized,
    config: &ModelConfig,
) -> Result<Array2<f32>> {
    let input_ids_view: ArrayView2<'_, i64> =
        ArrayView2::from_shape((tokenized.rows, tokenized.cols), tokenized.input_ids.as_slice())?;
    let attn_masks_view: ArrayView2<'_, i64> =
        ArrayView2::from_shape((tokenized.rows, tokenized.cols), tokenized.attn_masks.as_slice())?;

    let mut inputs = Vec::with_capacity(2 + usize::from(tokenized.type_ids.is_some()));
    inputs.push((
        "input_ids",
        SessionInputValue::from(Value::from_array(input_ids_view)?),
    ));
    if config.with_attention_mask {
        inputs.push((
            "attention_mask",
            SessionInputValue::from(Value::from_array(attn_masks_view)?),
        ));
    }
    if let Some(type_ids) = tokenized.type_ids.as_deref() {
        let type_ids_view: ArrayView2<'_, i64> =
            ArrayView2::from_shape((tokenized.rows, tokenized.cols), type_ids)?;
        inputs.push((
            "token_type_ids",
            SessionInputValue::from(Value::from_array(type_ids_view)?),
        ));
    }

    let outputs = session.run(inputs)?;
    let tensor_value = outputs.get(config.output_tensor.as_str()).ok_or_else(|| {
        GteError::Inference(format!(
            "output tensor '{}' not found in model outputs",
            &config.output_tensor
        ))
    })?;

    let array = tensor_value.try_extract_tensor::<f32>()?;

    match config.mode {
        ExtractorMode::Token(idx) => {
            let shape = array.shape();
            if shape.len() != 3 || idx >= shape[1] {
                return Err(GteError::Inference(format!(
                    "token extraction index {} out of bounds for output shape {:?}",
                    idx, shape
                )));
            }
            Ok(array.slice(ndarray::s![.., idx, ..]).into_owned())
        }
        ExtractorMode::MeanPool => {
            let ndim = array.ndim();
            let hidden_states = array.into_dimensionality::<ndarray::Ix3>().map_err(|_| {
                GteError::Inference(format!(
                    "mean pooling requires rank-3 output, got rank {}",
                    ndim
                ))
            })?;
            mean_pool(hidden_states, attn_masks_view)
        }
        ExtractorMode::Raw => Ok(array.into_dimensionality::<Ix2>()?.into_owned()),
    }
}
