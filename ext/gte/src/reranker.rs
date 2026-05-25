use crate::error::{GteError, Result};
use crate::model_config::{ModelLoadOverrides, PaddingMode};
use crate::model_profile::{
    has_input, read_tokenizer_profile, resolve_default_text_model, resolve_named_model, resolve_tokenizer_path,
    select_output_tensor, validate_supported_text_inputs,
};
use crate::pipeline::{extract_output_tensor, InputTensors};
use crate::postprocess::sigmoid_scores;
use crate::session::{build_session, SessionPool};
use crate::tokenizer::{parse_padding_mode_override, Tokenizer};
use std::path::{Path, PathBuf};

#[derive(Debug, Clone)]
struct RerankerConfig {
    max_length: usize,
    padding_mode: PaddingMode,
    output_tensor: String,
    with_type_ids: bool,
    with_attention_mask: bool,
}

pub struct Reranker {
    tokenizer: Tokenizer,
    pool: SessionPool,
    config: RerankerConfig,
}

impl Reranker {
    pub fn from_dir<P: AsRef<Path>>(dir: P, optimization_level: u8, overrides: ModelLoadOverrides<'_>) -> Result<Self> {
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

        let probe_config = crate::model_config::ModelConfig {
            max_length,
            padding_mode,
            output_tensor: String::new(),
            mode: crate::model_config::ExtractorMode::Raw,
            with_type_ids: false,
            with_attention_mask: true,
            optimization_level,
            execution_providers: overrides.execution_providers.map(str::to_string),
            lowercase_input: false,
            max_input_chars: None,
        };
        let session = build_session(&model_path, &probe_config)?;

        validate_supported_text_inputs(&session, "text reranking")?;
        let with_type_ids = has_input(&session, "token_type_ids");
        let with_attention_mask = has_input(&session, "attention_mask");
        let output_tensor = select_output_tensor(&session, overrides.output_tensor, &["logits"])?;

        let config = RerankerConfig { max_length, padding_mode, output_tensor, with_type_ids, with_attention_mask };

        let tokenizer = Tokenizer::new(
            &tokenizer_path,
            config.max_length,
            config.with_type_ids,
            config.padding_mode,
            tokenizer_profile.fixed_padding_length,
        )?;

        let model_config = crate::model_config::ModelConfig {
            max_length,
            padding_mode,
            output_tensor: config.output_tensor.clone(),
            mode: crate::model_config::ExtractorMode::Raw,
            with_type_ids: config.with_type_ids,
            with_attention_mask: config.with_attention_mask,
            optimization_level,
            execution_providers: None,
            lowercase_input: false,
            max_input_chars: None,
        };
        let pool = SessionPool::new(session, &model_path, &model_config)?;
        Ok(Self { tokenizer, pool, config })
    }

    pub fn score_pairs(&self, pairs: &[(String, String)], apply_sigmoid: bool) -> Result<Vec<f32>> {
        let tokenized = self.tokenizer.tokenize_pairs(pairs)?;
        self.score_tokenized(&tokenized, apply_sigmoid)
    }

    pub fn score(&self, query: &str, candidates: &[String], apply_sigmoid: bool) -> Result<Vec<f32>> {
        let tokenized = self.tokenizer.tokenize_query_candidates(query, candidates)?;
        self.score_tokenized(&tokenized, apply_sigmoid)
    }

    fn score_tokenized(&self, tokenized: &crate::tokenizer::Tokenized, apply_sigmoid: bool) -> Result<Vec<f32>> {
        let input_tensors = InputTensors::from_tokenized(tokenized, self.config.with_attention_mask)?;
        let output_name = self.config.output_tensor.clone();
        let inputs = input_tensors.inputs;

        self.pool.with_session(|session| {
            let outputs = session.run(inputs).map_err(|e| GteError::Ort(e.to_string()))?;

            let array = extract_output_tensor(&outputs, output_name.as_str())?;

            let mut scores = match array.ndim() {
                1 => array.into_dimensionality::<ndarray::Ix1>()?.to_vec(),
                2 => {
                    let shape = array.shape();
                    if shape[1] == 0 {
                        return Err(GteError::Inference(format!(
                            "reranker output '{output_name}' has invalid shape {shape:?}"
                        )));
                    }
                    array.slice(ndarray::s![.., 0]).to_vec()
                }
                n => {
                    return Err(GteError::Inference(format!(
                        "reranker output '{output_name}' rank {n} is unsupported; expected rank 1 or 2"
                    )))
                }
            };

            if apply_sigmoid {
                sigmoid_scores(ndarray::ArrayViewMut1::from(scores.as_mut_slice()));
            }

            Ok(scores)
        })
    }
}
