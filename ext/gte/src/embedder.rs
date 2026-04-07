use crate::error::{GteError, Result};
use crate::model_config::{ExtractorMode, ModelConfig};
use crate::session::{build_session, run_session};
use crate::tokenizer::{Tokenized, Tokenizer};
use ndarray::Array2;
use ort::session::Session;
use std::path::{Path, PathBuf};

/// The main inference orchestrator for Phase 2.
/// Holds all initialized state: tokenizer, ORT session, model config.
/// Phase 3 will wrap this in a #[wrap] magnus struct for Ruby FFI.
pub struct Embedder {
    tokenizer: Tokenizer,
    session: Session,
    config: ModelConfig,
}

impl Embedder {
    /// Initialize the embedder from file paths and a model config.
    ///
    /// # Arguments
    /// - `tokenizer_path`: path to tokenizer.json
    /// - `model_path`: path to model.onnx
    /// - `config`: ModelConfig with max_length, output_tensor, mode, with_type_ids
    ///
    /// # Example
    /// ```no_run
    /// use gte::embedder::Embedder;
    /// use gte::model_config::{ExtractorMode, ModelConfig};
    /// let config = ModelConfig {
    ///     max_length: 512,
    ///     output_tensor: "last_hidden_state".to_string(),
    ///     mode: ExtractorMode::MeanPool,
    ///     with_type_ids: true,
    ///     with_attention_mask: true,
    ///     num_threads: 0,
    ///     optimization_level: 3,
    /// };
    /// let embedder = Embedder::new("path/to/tokenizer.json", "path/to/model.onnx", config)?;
    /// # Ok::<(), gte::error::GteError>(())
    /// ```
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

    /// Initialize the embedder from a model directory, auto-inferring configuration.
    ///
    /// Expects directory layout:
    /// - `{dir}/tokenizer.json`
    /// - `{dir}/onnx/model.onnx`
    /// - `{dir}/tokenizer_config.json` (optional, for model_max_length)
    ///
    /// Inspects the ONNX model's inputs/outputs to determine:
    /// - whether token_type_ids and attention_mask are needed
    /// - whether unsupported inputs are required by this text-only API
    /// - which output tensor to use (deterministic preference order)
    /// - extraction mode (MeanPool for 3D output, Raw for 2D)
    pub fn from_dir<P: AsRef<Path>>(
        dir: P,
        num_threads: usize,
        optimization_level: u8,
    ) -> Result<Self> {
        let dir = dir.as_ref();

        // Resolve paths
        let tokenizer_path = dir.join("tokenizer.json");
        let model_path = resolve_model_path(dir)?;

        if !tokenizer_path.exists() {
            return Err(GteError::Tokenizer(format!(
                "tokenizer.json not found in {}",
                dir.display()
            )));
        }

        // Read max_length from tokenizer_config.json
        let max_length = read_max_length(dir);

        // Build session first to inspect inputs/outputs
        let temp_config = ModelConfig {
            max_length,
            output_tensor: String::new(),
            mode: ExtractorMode::Raw,
            with_type_ids: false,
            with_attention_mask: true,
            num_threads,
            optimization_level,
        };
        let session = build_session(&model_path, &temp_config)?;

        // Infer config from session
        validate_supported_inputs(&session)?;
        let with_type_ids = session.inputs.iter().any(|i| i.name == "token_type_ids");
        let with_attention_mask = session.inputs.iter().any(|i| i.name == "attention_mask");
        let output_tensor = select_output_tensor(&session)?;

        // Infer mode from output dimensions
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

    /// Tokenize a batch of strings and run the ONNX inference session.
    /// Returns a 2D array of shape [batch_size, embedding_dim].
    ///
    /// RUST-03: Embedding extraction mode is determined by self.config.mode.
    ///
    /// // L2 normalization is applied in Phase 3 (Ruby API layer)
    pub fn embed(&self, texts: Vec<String>) -> Result<Array2<f32>> {
        let tokenized = self.tokenizer.tokenize(texts)?;
        let embeddings = run_session(&self.session, &tokenized, &self.config)?;
        Ok(embeddings)
    }

    /// Tokenize texts for use with `run()` — split from embed() so the GVL
    /// can be released between tokenization and inference (per D-01).
    pub fn tokenize(&self, texts: &[String]) -> crate::error::Result<Tokenized> {
        self.tokenizer.tokenize(texts.to_vec())
    }

    /// Run ONNX session on pre-tokenized inputs — this is the call wrapped in rb_thread_call_without_gvl.
    pub fn run(&self, tokenized: &Tokenized) -> crate::error::Result<Array2<f32>> {
        run_session(&self.session, tokenized, &self.config)
    }
}

/// Resolve the ONNX model path within a directory.
/// Prefers text_model.onnx (text-only encoder for vision-language models) over
/// model.onnx (which may be a combined model requiring pixel_values).
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

fn validate_supported_inputs(session: &Session) -> Result<()> {
    let unsupported: Vec<String> = session
        .inputs
        .iter()
        .map(|input| input.name.clone())
        .filter(|name| name != "input_ids" && name != "attention_mask" && name != "token_type_ids")
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

/// Choose output tensor deterministically across known families before falling
/// back to the first output returned by ORT.
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

/// Read model_max_length from tokenizer_config.json, defaulting to 512, capped at 8192.
fn read_max_length(dir: &Path) -> usize {
    let config_path = dir.join("tokenizer_config.json");
    if let Ok(contents) = std::fs::read_to_string(&config_path) {
        if let Ok(json) = serde_json::from_str::<serde_json::Value>(&contents) {
            if let Some(value) = json.get("model_max_length") {
                if let Some(max_len) = value.as_u64() {
                    return (max_len as usize).min(8192);
                }
                if let Some(max_len) = value.as_i64() {
                    if max_len > 0 {
                        return (max_len as usize).min(8192);
                    }
                }
                let numeric_string = match value {
                    serde_json::Value::Number(n) => Some(n.to_string()),
                    serde_json::Value::String(s) => Some(s.clone()),
                    _ => None,
                };
                if let Some(raw) = numeric_string {
                    if let Ok(max_len) = raw.parse::<u128>() {
                        return max_len.min(8192) as usize;
                    }
                }
            }
        }
    }
    512
}

fn output_basename(name: &str) -> &str {
    name.rsplit('/').next().unwrap_or(name)
}

/// Infer extraction mode from the selected output tensor.
/// 3 dims => MeanPool (token embeddings), 2 dims => Raw (already pooled).
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

/// L2-normalize each row of an embedding matrix in-place.
/// Per D-08: normalization happens in Rust before FFI return.
/// If a row's norm is 0.0, leave it unchanged (avoid NaN).
pub fn normalize_l2(mut embeddings: Array2<f32>) -> Array2<f32> {
    for mut row in embeddings.rows_mut() {
        let norm = row.mapv(|x| x * x).sum().sqrt();
        if norm > 0.0 {
            row /= norm;
        }
    }
    embeddings
}
