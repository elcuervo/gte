use crate::error::{GteError, Result};
use crate::model_config::{ExtractorMode, ModelConfig};
use crate::model_profile::{
    has_input, infer_extraction_mode, read_max_length, resolve_default_text_model, resolve_named_model,
    resolve_tokenizer_path, select_output_tensor, validate_supported_text_inputs,
};
use crate::postprocess::normalize_l2 as normalize_l2_rows;
use crate::session::{build_session, run_session};
use crate::tokenizer::{Tokenized, Tokenizer};
use ndarray::Array2;
use ort::session::Session;
use std::path::Path;

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
        const PREFERRED_EMBEDDING_OUTPUTS: [&str; 4] = [
            "pooler_output",
            "text_embeds",
            "sentence_embedding",
            "last_hidden_state",
        ];

        let dir = dir.as_ref();
        let tokenizer_path = resolve_tokenizer_path(dir)?;
        let model_path = match model_name.filter(|s| !s.is_empty()) {
            Some(name) => resolve_named_model(dir, name)?,
            None => resolve_default_text_model(dir)?,
        };

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

        validate_supported_text_inputs(&session, "text embedding")?;
        let with_type_ids = has_input(&session, "token_type_ids");
        let with_attention_mask = has_input(&session, "attention_mask");
        let output_tensor =
            select_output_tensor(&session, output_tensor_override, &PREFERRED_EMBEDDING_OUTPUTS)?;
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

pub fn normalize_l2(embeddings: Array2<f32>) -> Array2<f32> {
    normalize_l2_rows(embeddings)
}
