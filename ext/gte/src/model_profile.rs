use crate::error::{GteError, Result};
use crate::model_config::ExtractorMode;
use ort::session::Session;
use serde_json::Value;
use std::path::{Path, PathBuf};

const SUPPORTED_INPUTS: [&str; 3] = ["input_ids", "attention_mask", "token_type_ids"];
const DEFAULT_MAX_LENGTH: usize = 512;
const MAX_SUPPORTED_LENGTH: usize = 8192;

#[derive(Debug, Clone, Copy)]
pub struct TokenizerProfile {
    pub default_max_length: usize,
    pub safe_max_length: usize,
    pub fixed_padding_length: Option<usize>,
}

pub fn resolve_tokenizer_path(dir: &Path) -> Result<PathBuf> {
    let tokenizer_path = dir.join("tokenizer.json");
    if !tokenizer_path.exists() {
        return Err(GteError::Tokenizer(format!(
            "tokenizer.json not found in {}",
            dir.display()
        )));
    }
    Ok(tokenizer_path)
}

pub fn resolve_named_model(dir: &Path, name: &str) -> Result<PathBuf> {
    let candidates = [dir.join("onnx").join(name), dir.join(name)];
    for path in &candidates {
        if path.exists() {
            return Ok(path.clone());
        }
    }
    Err(GteError::Inference(format!(
        "model '{}' not found in {} (checked onnx/{0} and {0})",
        name,
        dir.display()
    )))
}

pub fn resolve_default_text_model(dir: &Path) -> Result<PathBuf> {
    let candidates = [
        dir.join("onnx").join("text_model.onnx"),
        dir.join("text_model.onnx"),
        dir.join("onnx").join("model.onnx"),
        dir.join("model.onnx"),
    ];
    for path in &candidates {
        if path.exists() {
            return Ok(path.clone());
        }
    }
    Err(GteError::Inference(format!(
        "no ONNX model found in {} (checked text_model.onnx and model.onnx)",
        dir.display()
    )))
}

pub fn read_tokenizer_profile(dir: &Path) -> TokenizerProfile {
    let tokenizer_config = read_json(dir.join("tokenizer_config.json"));
    let tokenizer_json = read_json(dir.join("tokenizer.json"));

    let fixed_padding_length = tokenizer_json
        .as_ref()
        .and_then(parse_fixed_padding_length_from_tokenizer_json);

    let mut candidates = Vec::new();
    if let Some(config) = tokenizer_config.as_ref() {
        if let Some(v) = config.get("max_length").and_then(parse_positive_usize) {
            candidates.push(v.min(MAX_SUPPORTED_LENGTH));
        }
        if let Some(v) = config.get("model_max_length").and_then(parse_positive_usize) {
            candidates.push(v.min(MAX_SUPPORTED_LENGTH));
        }
    }

    if let Some(tokenizer) = tokenizer_json.as_ref() {
        if let Some(v) = tokenizer
            .get("truncation")
            .and_then(|truncation| truncation.get("max_length"))
            .and_then(parse_positive_usize)
        {
            candidates.push(v.min(MAX_SUPPORTED_LENGTH));
        }
    }

    if let Some(v) = fixed_padding_length {
        candidates.push(v.min(MAX_SUPPORTED_LENGTH));
    }

    let default_max_length = candidates
        .iter()
        .copied()
        .min()
        .unwrap_or(DEFAULT_MAX_LENGTH)
        .max(1);
    let safe_max_length = fixed_padding_length.unwrap_or(default_max_length).max(1);

    TokenizerProfile {
        default_max_length,
        safe_max_length,
        fixed_padding_length,
    }
}

fn read_json(path: PathBuf) -> Option<Value> {
    let contents = std::fs::read_to_string(path).ok()?;
    serde_json::from_str(&contents).ok()
}

fn parse_positive_usize(value: &Value) -> Option<usize> {
    let raw = value
        .as_u64()
        .or_else(|| {
            value
                .as_f64()
                .filter(|&v| v.is_finite() && v > 0.0)
                .map(|v| v as u64)
        })
        .or_else(|| value.as_str().and_then(|s| s.parse::<u64>().ok()))?;
    let parsed = usize::try_from(raw).ok()?;
    (parsed > 0).then_some(parsed)
}

fn parse_fixed_padding_length_from_tokenizer_json(tokenizer_json: &Value) -> Option<usize> {
    tokenizer_json
        .get("padding")
        .and_then(|padding| padding.get("strategy"))
        .and_then(|strategy| strategy.get("Fixed"))
        .and_then(parse_positive_usize)
}

pub fn validate_supported_text_inputs(session: &Session, api_label: &str) -> Result<()> {
    let unsupported: Vec<String> = session.inputs().iter()
        .filter(|i| !SUPPORTED_INPUTS.contains(&i.name()))
        .map(|i| i.name().to_owned())
        .collect();

    if unsupported.is_empty() {
        return Ok(());
    }

    let mut message = format!(
        "unsupported model inputs for {} API: {}",
        api_label,
        unsupported.join(", ")
    );
    if unsupported.iter().any(|n| n == "pixel_values") {
        message.push_str(
            ". This looks like a multimodal graph. Provide a text-only export (for example onnx/text_model.onnx).",
        );
    } else {
        message.push_str(". Supported inputs are: input_ids, attention_mask, token_type_ids.");
    }
    Err(GteError::Inference(message))
}

pub fn has_input(session: &Session, name: &str) -> bool {
    session.inputs().iter().any(|input| input.name() == name)
}

fn output_name_matches(name: &str, preferred: &str) -> bool {
    let lower = name.to_ascii_lowercase();
    lower == preferred || lower.ends_with(&format!("/{}", preferred))
}

pub fn select_output_tensor(
    session: &Session,
    requested: Option<&str>,
    preferred_outputs: &[&str],
) -> Result<String> {
    if let Some(requested_name) = requested.map(str::trim).filter(|name| !name.is_empty()) {
        if let Some(output) = session
            .outputs()
            .iter()
            .find(|o| output_name_matches(o.name(), requested_name))
        {
            return Ok(output.name().to_owned());
        }
        let available = session
            .outputs()
            .iter()
            .map(|o| o.name())
            .collect::<Vec<_>>()
            .join(", ");
        return Err(GteError::Inference(format!(
            "requested output tensor '{}' not found in model outputs: {}",
            requested_name, available
        )));
    }

    for preferred in preferred_outputs {
        if let Some(output) = session
            .outputs()
            .iter()
            .find(|o| output_name_matches(o.name(), preferred))
        {
            return Ok(output.name().to_owned());
        }
    }

    let outputs = session.outputs();
    let best = outputs
        .iter()
        .find(|o| {
            matches!(o.dtype(), ort::value::ValueType::Tensor { shape, .. } if shape.len() == 2)
        })
        .or_else(|| outputs.first());
    best.map(|o| o.name().to_owned())
        .ok_or_else(|| GteError::Inference("model has no outputs".into()))
}

fn output_basename(name: &str) -> &str {
    name.rsplit('/').next().unwrap_or(name)
}

pub fn infer_extraction_mode(session: &Session, output_tensor: &str) -> Result<ExtractorMode> {
    let output = session
        .outputs()
        .iter()
        .find(|o| o.name() == output_tensor)
        .ok_or_else(|| {
            GteError::Inference(format!(
                "output tensor '{}' not found in model outputs",
                output_tensor
            ))
        })?;

    let ndims = match output.dtype() {
        ort::value::ValueType::Tensor { shape, .. } => shape.len(),
        other => {
            return Err(GteError::Inference(format!(
                "output is not a tensor: {:?}",
                other
            )))
        }
    };

    match (output_basename(output_tensor), ndims) {
        ("last_hidden_state", 3) => Ok(ExtractorMode::MeanPool),
        (_, 2) => Ok(ExtractorMode::Raw),
        (_, 3) => Ok(ExtractorMode::MeanPool),
        (_, n) => Err(GteError::Inference(format!(
            "unexpected output tensor rank {} for '{}': expected 2 (Raw) or 3 (MeanPool)",
            n, output_tensor
        ))),
    }
}

#[cfg(test)]
mod tests {
    use super::{parse_fixed_padding_length_from_tokenizer_json, parse_positive_usize};
    use serde_json::json;

    #[test]
    fn parse_positive_usize_handles_integer_float_and_string() {
        assert_eq!(parse_positive_usize(&json!(64)), Some(64));
        assert_eq!(parse_positive_usize(&json!(64.0)), Some(64));
        assert_eq!(parse_positive_usize(&json!("64")), Some(64));
        assert_eq!(parse_positive_usize(&json!(0)), None);
    }

    #[test]
    fn parse_fixed_padding_length_reads_fixed_padding_strategy() {
        let tokenizer_json = json!({
            "padding": {
                "strategy": {
                    "Fixed": 64
                }
            }
        });
        assert_eq!(
            parse_fixed_padding_length_from_tokenizer_json(&tokenizer_json),
            Some(64)
        );
    }
}
