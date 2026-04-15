use crate::error::{GteError, Result};
use crate::model_config::{ExtractorMode, ModelConfig};
use crate::postprocess::normalize_l2 as normalize_l2_rows;
use crate::session::{build_session, run_session};
use crate::tokenizer::{Tokenized, Tokenizer};
use ndarray::Array2;
use ort::session::Session;
use std::path::{Path, PathBuf};

pub struct Embedder {
    tokenizer: Tokenizer,
    session: Session,
    config: ModelConfig,
}

impl Embedder {
    pub fn new<P1, P2>(tokenizer_path: P1, model_path: P2, config: ModelConfig) -> Result<Self>
    where
        P1: AsRef<Path>,
        P2: AsRef<Path>,
    {
        let tokenizer = Tokenizer::new(tokenizer_path, config.max_length, config.with_type_ids)?;
        let session = build_session(model_path, &config)?;
        Ok(Self {
            tokenizer,
            session,
            config,
        })
    }

    pub fn from_dir<P: AsRef<Path>>(
        dir: P,
        num_threads: usize,
        optimization_level: u8,
        model_name: Option<&str>,
        output_tensor_override: Option<&str>,
        max_length_override: Option<usize>,
    ) -> Result<Self> {
        let dir = dir.as_ref();
        let tokenizer_path = dir.join("tokenizer.json");
        let model_path = match model_name.filter(|s| !s.is_empty()) {
            Some(name) => resolve_named_model(dir, name)?,
            None => resolve_model_path(dir)?,
        };

        if !tokenizer_path.exists() {
            return Err(GteError::Tokenizer(format!(
                "tokenizer.json not found in {}",
                dir.display()
            )));
        }

        let max_length = if let Some(override_value) = max_length_override {
            if override_value == 0 {
                return Err(GteError::Inference(
                    "max_length override must be greater than 0".to_string(),
                ));
            }
            override_value
        } else {
            read_max_length(dir)
        };
        let session_config = ModelConfig {
            max_length,
            output_tensor: String::new(),
            mode: ExtractorMode::Raw,
            with_type_ids: false,
            with_attention_mask: true,
            num_threads,
            optimization_level,
        };
        let session = build_session(&model_path, &session_config)?;

        validate_supported_inputs(&session)?;
        let with_type_ids = session.inputs.iter().any(|i| i.name == "token_type_ids");
        let with_attention_mask = session.inputs.iter().any(|i| i.name == "attention_mask");
        let output_tensor = select_output_tensor(&session, output_tensor_override)?;
        let mode = infer_extraction_mode(&session, output_tensor.as_str())?;
        if matches!(mode, ExtractorMode::MeanPool) && !with_attention_mask {
            return Err(GteError::Inference(
                "cannot use mean pooling without attention_mask input".to_string(),
            ));
        }

        let config = ModelConfig {
            max_length,
            output_tensor,
            mode,
            with_type_ids,
            with_attention_mask,
            num_threads,
            optimization_level,
        };

        let tokenizer = Tokenizer::new(&tokenizer_path, config.max_length, config.with_type_ids)?;

        Ok(Self {
            tokenizer,
            session,
            config,
        })
    }

    pub fn embed(&self, texts: Vec<String>) -> Result<Array2<f32>> {
        let tokenized = self.tokenize(&texts)?;
        self.run(&tokenized)
    }

    pub fn tokenize(&self, texts: &[String]) -> crate::error::Result<Tokenized> {
        self.tokenizer.tokenize(texts)
    }

    pub fn run(&self, tokenized: &Tokenized) -> crate::error::Result<Array2<f32>> {
        run_session(&self.session, tokenized, &self.config)
    }
}

fn resolve_named_model(dir: &Path, name: &str) -> Result<PathBuf> {
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

fn resolve_model_path(dir: &Path) -> Result<PathBuf> {
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

const SUPPORTED_INPUTS: [&str; 3] = ["input_ids", "attention_mask", "token_type_ids"];

fn validate_supported_inputs(session: &Session) -> Result<()> {
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
        "unsupported model inputs for text embedding API: {}",
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

fn output_name_matches(name: &str, preferred: &str) -> bool {
    let lower = name.to_ascii_lowercase();
    lower == preferred || lower.ends_with(&format!("/{}", preferred))
}

fn select_output_tensor(session: &Session, requested: Option<&str>) -> Result<String> {
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

    const PREFERRED: [&str; 4] = [
        "pooler_output",
        "text_embeds",
        "sentence_embedding",
        "last_hidden_state",
    ];

    for preferred in PREFERRED {
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

fn read_max_length(dir: &Path) -> usize {
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

fn output_basename(name: &str) -> &str {
    name.rsplit('/').next().unwrap_or(name)
}

fn infer_extraction_mode(session: &Session, output_tensor: &str) -> Result<ExtractorMode> {
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

pub fn normalize_l2(embeddings: Array2<f32>) -> Array2<f32> {
    normalize_l2_rows(embeddings)
}
