use crate::error::{GteError, Result};
use crate::model_config::PaddingMode;
use std::path::Path;
use tokenizers::{PaddingParams, PaddingStrategy, TruncationParams};

pub struct Tokenized {
    pub rows: usize,
    pub cols: usize,
    pub input_ids: Vec<i64>,
    pub attn_masks: Vec<i64>,
    pub type_ids: Option<Vec<i64>>,
}

pub struct Tokenizer {
    tokenizer: tokenizers::Tokenizer,
    with_type_ids: bool,
}

impl Tokenizer {
    pub fn new<P: AsRef<Path>>(
        tokenizer_path: P,
        max_length: usize,
        with_type_ids: bool,
        padding_mode: PaddingMode,
        fixed_padding_length: Option<usize>,
    ) -> Result<Self> {
        #[allow(unused_results)]
        {
            let mut tokenizer =
                tokenizers::Tokenizer::from_file(tokenizer_path).map_err(|e| GteError::Tokenizer(e.to_string()))?;

            let truncation = TruncationParams { max_length, ..Default::default() };
            let padding = PaddingParams {
                strategy: resolve_padding_strategy(padding_mode, max_length, fixed_padding_length),
                ..Default::default()
            };
            tokenizer.with_truncation(Some(truncation)).map_err(|e| GteError::Tokenizer(e.to_string()))?;
            tokenizer.with_padding(Some(padding));

            Ok(Self { tokenizer, with_type_ids })
        }
    }

    pub fn tokenize(&self, texts: &[String]) -> Result<Tokenized> {
        if texts.len() == 1 {
            let encoding =
                self.tokenizer.encode_fast(texts[0].as_str(), true).map_err(|e| GteError::Tokenizer(e.to_string()))?;
            return Ok(build_tokenized_single(&encoding, self.with_type_ids));
        }

        let encode_inputs: Vec<&str> = texts.iter().map(String::as_str).collect();
        let encodings =
            self.tokenizer.encode_batch_fast(encode_inputs, true).map_err(|e| GteError::Tokenizer(e.to_string()))?;

        Ok(build_tokenized(&encodings, self.with_type_ids))
    }

    pub fn tokenize_pairs(&self, pairs: &[(String, String)]) -> Result<Tokenized> {
        let encode_inputs: Vec<tokenizers::EncodeInput<'_>> =
            pairs.iter().map(|(left, right)| (left.as_str(), right.as_str()).into()).collect();
        let encodings =
            self.tokenizer.encode_batch_fast(encode_inputs, true).map_err(|e| GteError::Tokenizer(e.to_string()))?;
        Ok(build_tokenized(&encodings, self.with_type_ids))
    }

    pub fn tokenize_query_candidates(&self, query: &str, candidates: &[String]) -> Result<Tokenized> {
        let encode_inputs: Vec<tokenizers::EncodeInput<'_>> =
            candidates.iter().map(|candidate| (query, candidate.as_str()).into()).collect();
        let encodings =
            self.tokenizer.encode_batch_fast(encode_inputs, true).map_err(|e| GteError::Tokenizer(e.to_string()))?;
        Ok(build_tokenized(&encodings, self.with_type_ids))
    }
}

pub fn parse_padding_mode_override(value: Option<&str>) -> Result<Option<PaddingMode>> {
    let Some(raw) = value.map(str::trim).filter(|v| !v.is_empty()) else {
        return Ok(None);
    };

    let normalized = raw.to_ascii_lowercase().replace('-', "_");
    let parsed = match normalized.as_str() {
        "auto" => PaddingMode::Auto,
        "batch_longest" | "batchlongest" => PaddingMode::BatchLongest,
        "fixed" => PaddingMode::Fixed,
        _ => {
            return Err(GteError::Inference(format!(
                "invalid padding mode '{raw}'; expected one of: auto, batch_longest, fixed"
            )))
        }
    };
    Ok(Some(parsed))
}

fn resolve_padding_strategy(
    padding_mode: PaddingMode,
    max_length: usize,
    _fixed_padding_length: Option<usize>,
) -> PaddingStrategy {
    match padding_mode {
        PaddingMode::BatchLongest | PaddingMode::Auto => PaddingStrategy::BatchLongest,
        PaddingMode::Fixed => PaddingStrategy::Fixed(max_length),
    }
}

fn build_tokenized_single(encoding: &tokenizers::Encoding, with_type_ids: bool) -> Tokenized {
    let cols = encoding.len();

    let input_ids: Vec<i64> = encoding.get_ids().iter().map(|&value| i64::from(value)).collect();
    let attn_masks: Vec<i64> = encoding.get_attention_mask().iter().map(|&value| i64::from(value)).collect();
    let type_ids: Option<Vec<i64>> =
        with_type_ids.then(|| encoding.get_type_ids().iter().map(|&value| i64::from(value)).collect());

    Tokenized { rows: 1, cols, input_ids, attn_masks, type_ids }
}

fn build_tokenized(encodings: &[tokenizers::Encoding], with_type_ids: bool) -> Tokenized {
    let rows = encodings.len();
    let cols = encodings.first().map_or(0, tokenizers::Encoding::len);
    let len = rows * cols;

    let mut input_ids = Vec::with_capacity(len);
    let mut attn_masks = Vec::with_capacity(len);
    let mut type_ids = with_type_ids.then(|| Vec::with_capacity(len));

    for encoding in encodings {
        for &value in encoding.get_ids() {
            input_ids.push(i64::from(value));
        }
        for &value in encoding.get_attention_mask() {
            attn_masks.push(i64::from(value));
        }

        if let Some(type_ids) = type_ids.as_mut() {
            for &value in encoding.get_type_ids() {
                type_ids.push(i64::from(value));
            }
        }
    }

    Tokenized { rows, cols, input_ids, attn_masks, type_ids }
}

#[cfg(test)]
mod tests {
    use super::{parse_padding_mode_override, resolve_padding_strategy};
    use crate::model_config::PaddingMode;
    use tokenizers::PaddingStrategy;

    #[test]
    fn parse_padding_mode_override_accepts_expected_values() {
        assert_eq!(parse_padding_mode_override(Some("auto")).unwrap(), Some(PaddingMode::Auto));
        assert_eq!(parse_padding_mode_override(Some("batch-longest")).unwrap(), Some(PaddingMode::BatchLongest));
        assert_eq!(parse_padding_mode_override(Some("fixed")).unwrap(), Some(PaddingMode::Fixed));
    }

    #[test]
    fn parse_padding_mode_override_rejects_invalid_values() {
        assert!(parse_padding_mode_override(Some("unknown")).is_err());
    }

    #[test]
    fn resolve_padding_strategy_auto_always_uses_batch_longest() {
        // Auto ignores fixed_padding_length from tokenizer.json — BatchLongest is
        // always faster for inference and correct for variable-length inputs.
        // Use PaddingMode::Fixed explicitly when fixed-length padding is required.
        assert!(matches!(resolve_padding_strategy(PaddingMode::Auto, 64, Some(64)), PaddingStrategy::BatchLongest));
        assert!(matches!(resolve_padding_strategy(PaddingMode::Auto, 512, None), PaddingStrategy::BatchLongest));
    }

    #[test]
    fn resolve_padding_strategy_fixed_uses_max_length() {
        assert!(matches!(resolve_padding_strategy(PaddingMode::Fixed, 64, None), PaddingStrategy::Fixed(64)));
    }
}
