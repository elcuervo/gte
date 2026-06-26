use crate::error::{GteError, Result};
use crate::model_config::{ExtractorMode, ModelConfig, ModelLoadOverrides, PaddingMode};
use crate::model_profile::{
    has_input, infer_extraction_mode, read_tokenizer_profile, resolve_default_text_model, resolve_named_model,
    resolve_tokenizer_path, select_output_tensor, validate_supported_text_inputs,
};
use crate::postprocess::normalize_l2 as normalize_l2_rows;
use crate::session::{build_session, resolve_pool_size, run_session, SessionPool};
use crate::tokenizer::{parse_padding_mode_override, Tokenizer};
use ndarray::Array2;
use std::path::{Path, PathBuf};

pub struct Embedder {
    tokenizer: Tokenizer,
    pool: SessionPool,
    pub config: ModelConfig,
    normalize: bool,
}

impl Embedder {
    pub fn from_dir<P: AsRef<Path>>(dir: P, optimization_level: u8, overrides: ModelLoadOverrides<'_>) -> Result<Self> {
        const PREFERRED_EMBEDDING_OUTPUTS: [&str; 4] =
            ["pooler_output", "text_embeds", "sentence_embedding", "last_hidden_state"];

        let dir = dir.as_ref();
        let tokenizer_path = resolve_tokenizer_path(dir)?;
        let model_path: PathBuf = match overrides.model_name.filter(|s| !s.is_empty()) {
            Some(name) => resolve_named_model(dir, name)?,
            None => resolve_default_text_model(dir)?,
        };

        let tokenizer_profile = read_tokenizer_profile(dir);
        let max_length = if let Some(override_value) = overrides.max_length {
            if override_value == 0 {
                return Err(GteError::Inference("max_length override must be greater than 0".to_string()));
            }
            override_value.min(tokenizer_profile.safe_max_length)
        } else {
            tokenizer_profile.default_max_length
        };
        let padding_mode = parse_padding_mode_override(overrides.padding)?.unwrap_or(PaddingMode::Auto);

        let probe_config = ModelConfig {
            max_length,
            padding_mode,
            output_tensor: String::new(),
            mode: ExtractorMode::Raw,
            with_type_ids: false,
            with_attention_mask: true,
            optimization_level,
            execution_providers: overrides.execution_providers.map(str::to_string),
        };
        let session = build_session(&model_path, &probe_config)?;

        validate_supported_text_inputs(&session, "text embedding")?;
        let with_type_ids = has_input(&session, "token_type_ids");
        let with_attention_mask = has_input(&session, "attention_mask");
        let output_tensor = select_output_tensor(&session, overrides.output_tensor, &PREFERRED_EMBEDDING_OUTPUTS)?;
        let mode = infer_extraction_mode(&session, output_tensor.as_str())?;
        if matches!(mode, ExtractorMode::MeanPool) && !with_attention_mask {
            return Err(GteError::Inference("cannot use mean pooling without attention_mask input".to_string()));
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
        };

        let normalize = should_normalize_output(&config.output_tensor);

        let tokenizer = Tokenizer::new(
            &tokenizer_path,
            config.max_length,
            config.with_type_ids,
            config.padding_mode,
            tokenizer_profile.fixed_padding_length,
        )?;

        let pool_size = resolve_pool_size();
        let pool = SessionPool::new(&model_path, &config, pool_size)?;
        Ok(Self { tokenizer, pool, config, normalize })
    }

    pub fn embed(&self, texts: &[String]) -> Result<Array2<f32>> {
        let tokenized = self.tokenizer.tokenize(texts)?;
        let embeddings = self.pool.with_session(|session| run_session(session, &tokenized, &self.config))?;
        if self.normalize {
            Ok(normalize_l2_rows(embeddings))
        } else {
            Ok(embeddings)
        }
    }

    pub fn tokenize(&self, texts: &[String]) -> Result<crate::tokenizer::Tokenized> {
        self.tokenizer.tokenize(texts)
    }
}

fn should_normalize_output(name: &str) -> bool {
    let lower = name.to_ascii_lowercase();
    let base = lower.rsplit('/').next().unwrap_or(&lower);
    !(base.contains("normalized") || base.contains("l2_norm") || base.contains("l2norm"))
}

#[cfg(test)]
mod normalize_tests {
    use super::should_normalize_output;

    #[test]
    fn detects_normalized_output_names() {
        assert!(!should_normalize_output("pooled_sentence_embeddings_debiased_normalized"));
        assert!(!should_normalize_output("embeddings/L2_Normalized"));
        assert!(!should_normalize_output("l2norm_output"));
        assert!(!should_normalize_output("norm/l2_norm_tensor"));
    }

    #[test]
    fn does_not_detect_raw_output_names() {
        assert!(should_normalize_output("last_hidden_state"));
        assert!(should_normalize_output("text_embeds"));
        assert!(should_normalize_output("pooler_output"));
        assert!(should_normalize_output("sentence_embedding"));
        assert!(should_normalize_output("logits"));
    }
}
