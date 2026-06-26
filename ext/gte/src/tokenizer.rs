use crate::error::{GteError, Result};
use crate::model_config::PaddingMode;
use ndarray::Array2;
use std::path::Path;
use tokenizers::{PaddingParams, PaddingStrategy, TruncationParams};

pub struct Tokenized {
    pub input_ids: Array2<i64>,
    pub attn_masks: Array2<i64>,
    pub type_ids: Option<Array2<i64>>,
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
        {
            let mut tokenizer =
                tokenizers::Tokenizer::from_file(tokenizer_path).map_err(|e| GteError::Tokenizer(e.to_string()))?;

            let truncation = TruncationParams { max_length, ..Default::default() };
            let padding = PaddingParams {
                strategy: resolve_padding_strategy(padding_mode, max_length, fixed_padding_length),
                ..Default::default()
            };
            let _ = tokenizer.with_truncation(Some(truncation)).map_err(|e| GteError::Tokenizer(e.to_string()))?;
            let _ = tokenizer.with_padding(Some(padding));

            Ok(Self { tokenizer, with_type_ids })
        }
    }

    pub fn tokenize(&self, texts: &[String]) -> Result<Tokenized> {
        if texts.is_empty() {
            return Ok(Tokenized { input_ids: Array2::zeros((0, 0)), attn_masks: Array2::zeros((0, 0)), type_ids: None });
        }

        let encode_inputs: Vec<&str> = texts.iter().map(String::as_str).collect();
        let encodings =
            self.tokenizer.encode_batch_fast(encode_inputs, true).map_err(|e| GteError::Tokenizer(e.to_string()))?;

        build_tokenized(&encodings, self.with_type_ids)
    }

    pub fn tokenize_pairs(&self, pairs: &[(String, String)]) -> Result<Tokenized> {
        if pairs.is_empty() {
            return Ok(Tokenized { input_ids: Array2::zeros((0, 0)), attn_masks: Array2::zeros((0, 0)), type_ids: None });
        }

        let encode_inputs: Vec<tokenizers::EncodeInput<'_>> =
            pairs.iter().map(|(left, right)| (left.as_str(), right.as_str()).into()).collect();
        let encodings =
            self.tokenizer.encode_batch_fast(encode_inputs, true).map_err(|e| GteError::Tokenizer(e.to_string()))?;
        build_tokenized(&encodings, self.with_type_ids)
    }

    pub fn tokenize_query_candidates(&self, query: &str, candidates: &[String]) -> Result<Tokenized> {
        if candidates.is_empty() {
            return Ok(Tokenized { input_ids: Array2::zeros((0, 0)), attn_masks: Array2::zeros((0, 0)), type_ids: None });
        }

        let encode_inputs: Vec<tokenizers::EncodeInput<'_>> =
            candidates.iter().map(|candidate| (query, candidate.as_str()).into()).collect();
        let encodings =
            self.tokenizer.encode_batch_fast(encode_inputs, true).map_err(|e| GteError::Tokenizer(e.to_string()))?;
        build_tokenized(&encodings, self.with_type_ids)
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

fn to_i64(array: &[u32]) -> Vec<i64> {
    array.iter().map(|&v| v as i64).collect()
}

fn build_tokenized(encodings: &[tokenizers::Encoding], with_type_ids: bool) -> Result<Tokenized> {
    let rows = encodings.len();
    let cols = encodings.first().map_or(0, tokenizers::Encoding::len);
    if rows == 0 || cols == 0 {
        return Ok(Tokenized { input_ids: Array2::zeros((0, 0)), attn_masks: Array2::zeros((0, 0)), type_ids: None });
    }

    let mut input_ids = Array2::zeros((0, cols));
    let mut attn_masks = Array2::zeros((0, cols));
    let mut type_ids = with_type_ids.then(|| Array2::zeros((0, cols)));

    for encoding in encodings {
        input_ids.push_row(ndarray::ArrayView::from(&to_i64(encoding.get_ids())))?;
        attn_masks.push_row(ndarray::ArrayView::from(&to_i64(encoding.get_attention_mask())))?;
        if let Some(ref mut type_ids) = type_ids {
            type_ids.push_row(ndarray::ArrayView::from(&to_i64(encoding.get_type_ids())))?;
        }
    }

    Ok(Tokenized { input_ids, attn_masks, type_ids })
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
        assert!(matches!(resolve_padding_strategy(PaddingMode::Auto, 64, Some(64)), PaddingStrategy::BatchLongest));
        assert!(matches!(resolve_padding_strategy(PaddingMode::Auto, 512, None), PaddingStrategy::BatchLongest));
    }

    #[test]
    fn resolve_padding_strategy_fixed_uses_max_length() {
        assert!(matches!(resolve_padding_strategy(PaddingMode::Fixed, 64, None), PaddingStrategy::Fixed(64)));
    }
}
