use crate::error::{GteError, Result};
use crate::model_config::PaddingMode;
use crate::model_profile::{
    has_input, read_tokenizer_profile, resolve_default_text_model, resolve_named_model,
    resolve_tokenizer_path, select_output_tensor, validate_supported_text_inputs,
};
use crate::pipeline::{extract_output_tensor, InputTensors};
use crate::postprocess::sigmoid_scores;
use crate::session::build_session;
use crate::tokenizer::{parse_padding_mode_override, Tokenizer};
use ndarray::Array1;
use ort::session::Session;
use std::path::Path;

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
    session: Session,
    config: RerankerConfig,
}

impl Reranker {
    #[allow(clippy::too_many_arguments)]
    pub fn from_dir<P: AsRef<Path>>(
        dir: P,
        num_threads: usize,
        optimization_level: u8,
        model_name: Option<&str>,
        output_tensor_override: Option<&str>,
        max_length_override: Option<usize>,
        padding_override: Option<&str>,
        execution_providers_override: Option<&str>,
    ) -> Result<Self> {
        let dir = dir.as_ref();
        let tokenizer_path = resolve_tokenizer_path(dir)?;
        let model_path = match model_name.filter(|s| !s.is_empty()) {
            Some(name) => resolve_named_model(dir, name)?,
            None => resolve_default_text_model(dir)?,
        };

        let tokenizer_profile = read_tokenizer_profile(dir);
        let max_length = if let Some(override_value) = max_length_override {
            if override_value == 0 {
                return Err(GteError::Inference(
                    "max_length override must be greater than 0".to_string(),
                ));
            }
            override_value.min(tokenizer_profile.safe_max_length)
        } else {
            tokenizer_profile.default_max_length
        };
        let padding_mode = parse_padding_mode_override(padding_override)?.unwrap_or(PaddingMode::Auto);

        let probe_config = crate::model_config::ModelConfig {
            max_length,
            padding_mode,
            output_tensor: String::new(),
            mode: crate::model_config::ExtractorMode::Raw,
            with_type_ids: false,
            with_attention_mask: true,
            num_threads,
            optimization_level,
            execution_providers: execution_providers_override.map(str::to_string),
        };
        let session = build_session(&model_path, &probe_config)?;

        validate_supported_text_inputs(&session, "text reranking")?;
        let with_type_ids = has_input(&session, "token_type_ids");
        let with_attention_mask = has_input(&session, "attention_mask");
        let output_tensor = select_output_tensor(&session, output_tensor_override, &["logits"])?;

        let config = RerankerConfig {
            max_length,
            padding_mode,
            output_tensor,
            with_type_ids,
            with_attention_mask,
        };

        let tokenizer = Tokenizer::new(
            &tokenizer_path,
            config.max_length,
            config.with_type_ids,
            config.padding_mode,
            tokenizer_profile.fixed_padding_length,
        )?;

        Ok(Self {
            tokenizer,
            session,
            config,
        })
    }

    pub fn score_pairs(&self, pairs: &[(String, String)], apply_sigmoid: bool) -> Result<Array1<f32>> {
        let tokenized = self.tokenizer.tokenize_pairs(pairs)?;
        let input_tensors = InputTensors::from_tokenized(&tokenized, self.config.with_attention_mask)?;
        let outputs = self.session.run(input_tensors.inputs)?;
        let array = extract_output_tensor(&outputs, self.config.output_tensor.as_str())?;

        let mut scores = match array.ndim() {
            1 => array.into_dimensionality::<ndarray::Ix1>()?.into_owned(),
            2 => {
                let shape = array.shape();
                if shape[1] == 0 {
                    return Err(GteError::Inference(format!(
                        "reranker output '{}' has invalid shape {:?}",
                        self.config.output_tensor, shape
                    )));
                }
                array.slice(ndarray::s![.., 0]).into_owned()
            }
            n => {
                return Err(GteError::Inference(format!(
                    "reranker output '{}' rank {} is unsupported; expected rank 1 or 2",
                    self.config.output_tensor, n
                )))
            }
        };

        if apply_sigmoid {
            sigmoid_scores(scores.view_mut());
        }

        Ok(scores)
    }

}
