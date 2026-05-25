use crate::error::{GteError, Result};
use crate::model_config::{ExtractorMode, ModelConfig, ModelLoadOverrides, PaddingMode};
use crate::model_profile::{
    has_input, infer_extraction_mode, read_tokenizer_profile, resolve_default_text_model,
    resolve_named_model, resolve_tokenizer_path, select_output_tensor, validate_supported_text_inputs,
};
use crate::postprocess::normalize_l2 as normalize_l2_rows;
use crate::session::{build_session, SessionPool};
use crate::tokenizer::{parse_padding_mode_override, Tokenized, Tokenizer};
use ndarray::Array2;
use std::path::{Path, PathBuf};

pub struct Embedder {
    tokenizer: Tokenizer,
    pool: SessionPool,
    pub config: ModelConfig,
}

impl Embedder {
    pub fn new<P1, P2>(tokenizer_path: P1, model_path: P2, config: ModelConfig) -> Result<Self>
    where
        P1: AsRef<Path>,
        P2: AsRef<Path>,
    {
        let tokenizer = Tokenizer::new(
            tokenizer_path,
            config.max_length,
            config.with_type_ids,
            config.padding_mode,
            None,
        )?;
        let model_path = model_path.as_ref();
        let session = build_session(model_path, &config)?;
        let pool = SessionPool::new(session, model_path, &config)?;
        Ok(Self { tokenizer, pool, config })
    }

    pub fn from_dir<P: AsRef<Path>>(
        dir: P,
        optimization_level: u8,
        overrides: ModelLoadOverrides<'_>,
    ) -> Result<Self> {
        const PREFERRED_EMBEDDING_OUTPUTS: [&str; 4] = [
            "pooler_output",
            "text_embeds",
            "sentence_embedding",
            "last_hidden_state",
        ];

        let dir = dir.as_ref();
        let tokenizer_path = resolve_tokenizer_path(dir)?;
        let model_path: PathBuf = match overrides.model_name.filter(|s| !s.is_empty()) {
            Some(name) => resolve_named_model(dir, name)?,
            None => resolve_default_text_model(dir)?,
        };

        let tokenizer_profile = read_tokenizer_profile(dir);
        let max_length = if let Some(override_value) = overrides.max_length {
            if override_value == 0 {
                return Err(GteError::Inference(
                    "max_length override must be greater than 0".to_string(),
                ));
            }
            override_value.min(tokenizer_profile.safe_max_length)
        } else {
            tokenizer_profile.default_max_length
        };
        let padding_mode =
            parse_padding_mode_override(overrides.padding)?.unwrap_or(PaddingMode::Auto);

        let session_config = ModelConfig {
            max_length,
            padding_mode,
            output_tensor: String::new(),
            mode: ExtractorMode::Raw,
            with_type_ids: false,
            with_attention_mask: true,
            optimization_level,
            execution_providers: overrides.execution_providers.map(str::to_string),
            lowercase_input: overrides.lowercase_input.unwrap_or(false),
            max_input_chars: overrides.max_input_chars,
        };
        let session = build_session(&model_path, &session_config)?;

        validate_supported_text_inputs(&session, "text embedding")?;
        let with_type_ids = has_input(&session, "token_type_ids");
        let with_attention_mask = has_input(&session, "attention_mask");
        let output_tensor =
            select_output_tensor(&session, overrides.output_tensor, &PREFERRED_EMBEDDING_OUTPUTS)?;
        let mode = infer_extraction_mode(&session, output_tensor.as_str())?;
        if matches!(mode, ExtractorMode::MeanPool) && !with_attention_mask {
            return Err(GteError::Inference(
                "cannot use mean pooling without attention_mask input".to_string(),
            ));
        }

        let config = ModelConfig {
            max_length,
            padding_mode,
            output_tensor,
            mode,
            with_type_ids,
            with_attention_mask,
            optimization_level,
            execution_providers: overrides.execution_providers.map(str::to_string),
            lowercase_input: overrides.lowercase_input.unwrap_or(false),
            max_input_chars: overrides.max_input_chars,
        };

        let tokenizer = Tokenizer::new(
            &tokenizer_path,
            config.max_length,
            config.with_type_ids,
            config.padding_mode,
            tokenizer_profile.fixed_padding_length,
        )?;

        let pool = SessionPool::new(session, &model_path, &session_config)?;
        Ok(Self { tokenizer, pool, config })
    }

    pub fn embed(&self, texts: Vec<String>) -> Result<Array2<f32>> {
        self.embed_ref(&texts)
    }

    pub fn embed_ref(&self, texts: &[String]) -> Result<Array2<f32>> {
        let sanitized: Vec<String>;
        let input = if self.config.lowercase_input || self.config.max_input_chars.is_some() {
            sanitized = texts
                .iter()
                .map(|t| {
                    let mut s = if self.config.lowercase_input {
                        t.to_lowercase()
                    } else {
                        t.clone()
                    };
                    if let Some(max_chars) = self.config.max_input_chars {
                        s.truncate(max_chars.min(s.len()));
                    }
                    s
                })
                .collect();
            &sanitized
        } else {
            texts
        };
        let tokenized = self.tokenize(input)?;
        self.run(&tokenized)
    }

    pub fn tokenize(&self, texts: &[String]) -> crate::error::Result<Tokenized> {
        self.tokenizer.tokenize(texts)
    }

    pub fn run(&self, tokenized: &Tokenized) -> crate::error::Result<Array2<f32>> {
        self.pool.run(tokenized, &self.config)
    }
}

pub fn normalize_l2(embeddings: Array2<f32>) -> Array2<f32> {
    normalize_l2_rows(embeddings)
}

pub fn output_name_suggests_normalized(name: &str) -> bool {
    let lower = name.to_ascii_lowercase();
    let base = lower.rsplit('/').next().unwrap_or(&lower);
    base.contains("normalized")
        || base.contains("l2_norm")
        || base.contains("l2norm")
}

#[cfg(test)]
mod normalize_tests {
    use super::output_name_suggests_normalized;

    #[test]
    fn detects_normalized_output_names() {
        assert!(output_name_suggests_normalized("pooled_sentence_embeddings_debiased_normalized"));
        assert!(output_name_suggests_normalized("embeddings/L2_Normalized"));
        assert!(output_name_suggests_normalized("l2norm_output"));
        assert!(output_name_suggests_normalized("norm/l2_norm_tensor"));
    }

    #[test]
    fn does_not_detect_raw_output_names() {
        assert!(!output_name_suggests_normalized("last_hidden_state"));
        assert!(!output_name_suggests_normalized("text_embeds"));
        assert!(!output_name_suggests_normalized("pooler_output"));
        assert!(!output_name_suggests_normalized("sentence_embedding"));
        assert!(!output_name_suggests_normalized("logits"));
    }
}
