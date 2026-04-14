use crate::error::{GteError, Result};
use crate::model_config::{ExtractorMode, ModelConfig};
use crate::postprocess::normalize_l2 as normalize_l2_rows;
use crate::session::{build_session, run_session};
use crate::tokenizer::{Tokenized, Tokenizer};
use ndarray::Array2;
use ort::session::Session;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ModelFamily {
    E5Like,
    SiglipLike,
    ClipLike,
    Other,
}

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

        let max_length = read_max_length(dir);
        let probe_num_threads = if num_threads == 0 { 1 } else { num_threads };
        let temp_config = ModelConfig {
            max_length,
            output_tensor: String::new(),
            mode: ExtractorMode::Raw,
            with_type_ids: false,
            with_attention_mask: true,
            num_threads: probe_num_threads,
            optimization_level,
        };
        let mut session = build_session(&model_path, &temp_config)?;

        validate_supported_inputs(&session)?;
        let with_type_ids = session.inputs.iter().any(|i| i.name == "token_type_ids");
        let with_attention_mask = session.inputs.iter().any(|i| i.name == "attention_mask");
        let output_tensor = select_output_tensor(&session)?;
        let output_base = output_basename(output_tensor.as_str()).to_string();
        let mode = infer_extraction_mode(&session, output_tensor.as_str())?;
        if matches!(mode, ExtractorMode::MeanPool) && !with_attention_mask {
            return Err(GteError::Inference(
                "cannot use mean pooling without attention_mask input".to_string(),
            ));
        }

        let tuned_num_threads = tune_num_threads(
            num_threads,
            with_attention_mask,
            with_type_ids,
            output_base.as_str(),
        );

        let config = ModelConfig {
            max_length,
            output_tensor,
            mode,
            with_type_ids,
            with_attention_mask,
            num_threads: tuned_num_threads,
            optimization_level,
        };

        if tuned_num_threads != probe_num_threads {
            // Release probe session before rebuilding to minimize transient peak RSS.
            drop(session);
            session = build_session(&model_path, &config)?;
        }

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

fn tune_num_threads(
    requested: usize,
    with_attention_mask: bool,
    with_type_ids: bool,
    output_name: &str,
) -> usize {
    if requested > 0 {
        return requested;
    }

    let family = infer_model_family(with_attention_mask, with_type_ids, output_name);

    match family {
        ModelFamily::E5Like | ModelFamily::ClipLike | ModelFamily::SiglipLike => 3,
        ModelFamily::Other => 0,
    }
}

fn infer_model_family(
    with_attention_mask: bool,
    with_type_ids: bool,
    output_name: &str,
) -> ModelFamily {
    if output_name == "last_hidden_state" && with_attention_mask && with_type_ids {
        return ModelFamily::E5Like;
    }
    if output_name == "last_hidden_state" && with_attention_mask && !with_type_ids {
        return ModelFamily::SiglipLike;
    }
    if output_name == "text_embeds" && !with_attention_mask {
        return ModelFamily::ClipLike;
    }
    ModelFamily::Other
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

fn select_output_tensor(session: &Session) -> Result<String> {
    const PREFERRED: [&str; 4] = [
        "text_embeds",
        "pooler_output",
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
        let n = v
            .as_u64()
            .or_else(|| v.as_f64().filter(|&f| f > 0.0 && f < 1e15).map(|f| f as u64))?;
        Some((n as usize).min(8192))
    })()
    .unwrap_or(512)
}

#[cfg(test)]
mod tests {
    use super::{infer_model_family, tune_num_threads, ModelFamily};

    #[test]
    fn infer_model_family_recognizes_known_signatures() {
        assert_eq!(
            infer_model_family(true, true, "last_hidden_state"),
            ModelFamily::E5Like
        );
        assert_eq!(
            infer_model_family(true, false, "last_hidden_state"),
            ModelFamily::SiglipLike
        );
        assert_eq!(
            infer_model_family(false, false, "text_embeds"),
            ModelFamily::ClipLike
        );
        assert_eq!(infer_model_family(true, false, "pooler_output"), ModelFamily::Other);
    }

    #[test]
    fn tune_num_threads_respects_requested_value() {
        assert_eq!(tune_num_threads(7, true, true, "last_hidden_state"), 7);
    }

    #[test]
    fn tune_num_threads_uses_three_threads_for_known_families() {
        assert_eq!(tune_num_threads(0, true, true, "last_hidden_state"), 3);
        assert_eq!(tune_num_threads(0, true, false, "last_hidden_state"), 3);
        assert_eq!(tune_num_threads(0, false, false, "text_embeds"), 3);
    }

    #[test]
    fn tune_num_threads_returns_ort_default_for_other_family() {
        assert_eq!(tune_num_threads(0, true, false, "pooler_output"), 0);
    }
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
