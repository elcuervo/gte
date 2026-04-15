use crate::error::{GteError, Result};
use crate::model_config::ExtractorMode;
use ort::session::Session;
use std::path::{Path, PathBuf};

const SUPPORTED_INPUTS: [&str; 3] = ["input_ids", "attention_mask", "token_type_ids"];

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

pub fn read_max_length(dir: &Path) -> usize {
    (|| -> Option<usize> {
        let contents = std::fs::read_to_string(dir.join("tokenizer_config.json")).ok()?;
        let json: serde_json::Value = serde_json::from_str(&contents).ok()?;
        let v = json.get("model_max_length")?;
        let n = v.as_u64().or_else(|| {
            v.as_f64()
                .filter(|&f| f > 0.0 && f < 1e15)
                .map(|f| f as u64)
        })?;
        Some((n as usize).min(8192))
    })()
    .unwrap_or(512)
}

pub fn validate_supported_text_inputs(session: &Session, api_label: &str) -> Result<()> {
    let unsupported: Vec<String> = session
        .inputs
        .iter()
        .filter(|i| !SUPPORTED_INPUTS.contains(&i.name.as_str()))
        .map(|i| i.name.clone())
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
    session.inputs.iter().any(|input| input.name == name)
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
            .outputs
            .iter()
            .find(|o| output_name_matches(o.name.as_str(), requested_name))
        {
            return Ok(output.name.clone());
        }
        let available = session
            .outputs
            .iter()
            .map(|o| o.name.as_str())
            .collect::<Vec<_>>()
            .join(", ");
        return Err(GteError::Inference(format!(
            "requested output tensor '{}' not found in model outputs: {}",
            requested_name, available
        )));
    }

    for preferred in preferred_outputs {
        if let Some(output) = session
            .outputs
            .iter()
            .find(|o| output_name_matches(o.name.as_str(), preferred))
        {
            return Ok(output.name.clone());
        }
    }

    session
        .outputs
        .first()
        .map(|o| o.name.clone())
        .ok_or_else(|| GteError::Inference("model has no outputs".into()))
}

fn output_basename(name: &str) -> &str {
    name.rsplit('/').next().unwrap_or(name)
}

pub fn infer_extraction_mode(session: &Session, output_tensor: &str) -> Result<ExtractorMode> {
    let output = session
        .outputs
        .iter()
        .find(|o| o.name == output_tensor)
        .ok_or_else(|| {
            GteError::Inference(format!(
                "output tensor '{}' not found in model outputs",
                output_tensor
            ))
        })?;

    let ndims = match &output.output_type {
        ort::value::ValueType::Tensor { dimensions, .. } => dimensions.len(),
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
