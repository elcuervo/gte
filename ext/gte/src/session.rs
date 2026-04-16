use crate::error::{GteError, Result};
use crate::model_config::{ExtractorMode, ModelConfig};
use crate::pipeline::{extract_output_tensor, InputTensors};
use crate::postprocess::mean_pool;
use crate::tokenizer::Tokenized;
use ndarray::{Array2, Ix2};
use ort::execution_providers::{
    CoreMLExecutionProvider, ExecutionProviderDispatch, XNNPACKExecutionProvider,
};
use ort::session::Session;
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

    let providers = preferred_execution_providers(config.execution_providers.as_deref());
    if !providers.is_empty() {
        builder = builder.with_execution_providers(providers)?;
    }

    if config.num_threads > 0 {
        builder = builder.with_intra_threads(config.num_threads)?;
    }

    Ok(builder.commit_from_file(model_path)?)
}

fn preferred_execution_providers(order_override: Option<&str>) -> Vec<ExecutionProviderDispatch> {
    let order = resolve_provider_order(order_override);

    let mut providers = Vec::new();
    for provider in parse_provider_registrations(order.as_str()) {
        match provider {
            "xnnpack" => {
                providers.push(XNNPACKExecutionProvider::default().build().fail_silently())
            }
            "coreml" => providers.push(CoreMLExecutionProvider::default().build().fail_silently()),
            _ => {}
        }
    }
    providers
}

fn resolve_provider_order(order_override: Option<&str>) -> String {
    let env_order = std::env::var("GTE_EXECUTION_PROVIDERS").ok();
    resolve_provider_order_with_env(order_override, env_order.as_deref())
}

fn resolve_provider_order_with_env(order_override: Option<&str>, env_order: Option<&str>) -> String {
    order_override
        .or(env_order)
        .unwrap_or("cpu")
        .to_ascii_lowercase()
}

fn parse_provider_registrations(order: &str) -> Vec<&str> {
    let mut providers = Vec::new();
    for provider in order.split(',').map(str::trim).filter(|p| !p.is_empty()) {
        match provider {
            "xnnpack" | "coreml" => providers.push(provider),
            "none" | "cpu" => {}
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
    let input_tensors = InputTensors::from_tokenized(tokenized, config.with_attention_mask)?;
    let outputs = session.run(input_tensors.inputs)?;
    let array = extract_output_tensor(&outputs, config.output_tensor.as_str())?;

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
            mean_pool(hidden_states.view(), input_tensors.attention_mask)
        }
        ExtractorMode::Raw => Ok(array.into_dimensionality::<Ix2>()?.into_owned()),
    }
}

#[cfg(test)]
mod tests {
    use super::{parse_provider_registrations, resolve_provider_order_with_env};

    #[test]
    fn parse_provider_registrations_keeps_supported_order() {
        let parsed = parse_provider_registrations("xnnpack,coreml");
        assert_eq!(parsed, vec!["xnnpack", "coreml"]);
    }

    #[test]
    fn parse_provider_registrations_treats_cpu_and_none_as_fallback() {
        assert!(parse_provider_registrations("cpu").is_empty());
        assert!(parse_provider_registrations("none").is_empty());
        assert!(parse_provider_registrations("none,cpu").is_empty());
    }

    #[test]
    fn parse_provider_registrations_ignores_unknowns_and_empties() {
        let parsed = parse_provider_registrations(" ,xnnpak,,xnnpack,unknown,coreml,");
        assert_eq!(parsed, vec!["xnnpack", "coreml"]);
    }

    #[test]
    fn resolve_provider_order_prefers_override() {
        assert_eq!(
            resolve_provider_order_with_env(Some("xnnpack"), Some("coreml")),
            "xnnpack"
        );
        assert_eq!(resolve_provider_order_with_env(Some("CPU"), None), "cpu");
    }

    #[test]
    fn resolve_provider_order_falls_back_to_env_then_cpu_default() {
        assert_eq!(resolve_provider_order_with_env(None, Some("coreml")), "coreml");
        assert_eq!(resolve_provider_order_with_env(None, None), "cpu");
    }
}
