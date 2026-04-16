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
        let mut tokenizer = tokenizers::Tokenizer::from_file(tokenizer_path)
            .map_err(|e| GteError::Tokenizer(e.to_string()))?;

        let truncation = TruncationParams {
            max_length,
            ..Default::default()
        };
        tokenizer
            .with_truncation(Some(truncation))
            .map_err(|e| GteError::Tokenizer(e.to_string()))?;

        let padding = PaddingParams {
            strategy: resolve_padding_strategy(padding_mode, max_length, fixed_padding_length),
            ..Default::default()
        };
        tokenizer.with_padding(Some(padding));

        Ok(Self {
            tokenizer,
            with_type_ids,
        })
    }

    pub fn tokenize(&self, texts: &[String]) -> Result<Tokenized> {
        if texts.len() == 1 {
            let encoding = self
                .tokenizer
                .encode_fast(texts[0].as_str(), true)
                .map_err(|e| GteError::Tokenizer(e.to_string()))?;
            return build_tokenized_single(&encoding, self.with_type_ids);
        }

        let encode_inputs: Vec<&str> = texts.iter().map(String::as_str).collect();
        let encodings = self
            .tokenizer
            .encode_batch_fast(encode_inputs, true)
            .map_err(|e| GteError::Tokenizer(e.to_string()))?;

        build_tokenized(&encodings, self.with_type_ids)
    }

    pub fn tokenize_pairs(&self, pairs: &[(String, String)]) -> Result<Tokenized> {
        let encode_inputs: Vec<tokenizers::EncodeInput<'_>> = pairs
            .iter()
            .map(|(left, right)| (left.as_str(), right.as_str()).into())
            .collect();
        let encodings = self
            .tokenizer
            .encode_batch_fast(encode_inputs, true)
            .map_err(|e| GteError::Tokenizer(e.to_string()))?;
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
                "invalid padding mode '{}'; expected one of: auto, batch_longest, fixed",
                raw
            )))
        }
    };
    Ok(Some(parsed))
}

fn resolve_padding_strategy(
    padding_mode: PaddingMode,
    max_length: usize,
    fixed_padding_length: Option<usize>,
) -> PaddingStrategy {
    match padding_mode {
        PaddingMode::BatchLongest => PaddingStrategy::BatchLongest,
        PaddingMode::Fixed => PaddingStrategy::Fixed(max_length),
        PaddingMode::Auto => {
            if fixed_padding_length.is_some() {
                PaddingStrategy::Fixed(max_length)
            } else {
                PaddingStrategy::BatchLongest
            }
        }
    }
}

fn build_tokenized_single(
    encoding: &tokenizers::Encoding,
    with_type_ids: bool,
) -> Result<Tokenized> {
    let cols = encoding.len();

    let input_ids: Vec<i64> = encoding
        .get_ids()
        .iter()
        .map(|&value| i64::from(value))
        .collect();
    let attn_masks: Vec<i64> = encoding
        .get_attention_mask()
        .iter()
        .map(|&value| i64::from(value))
        .collect();
    let type_ids: Option<Vec<i64>> = with_type_ids.then(|| {
        encoding
            .get_type_ids()
            .iter()
            .map(|&value| i64::from(value))
            .collect()
    });

    Ok(Tokenized {
        rows: 1,
        cols,
        input_ids,
        attn_masks,
        type_ids,
    })
}

fn build_tokenized(encodings: &[tokenizers::Encoding], with_type_ids: bool) -> Result<Tokenized> {
    let rows = encodings.len();
    let cols = encodings
        .first()
        .map(|encoding| encoding.len())
        .unwrap_or(0);
    let len = rows * cols;

    let mut input_ids = Vec::with_capacity(len);
    let mut attn_masks = Vec::with_capacity(len);
    let mut type_ids = with_type_ids.then(|| Vec::with_capacity(len));

    for encoding in encodings {
        input_ids.extend(encoding.get_ids().iter().map(|&value| i64::from(value)));
        attn_masks.extend(
            encoding
                .get_attention_mask()
                .iter()
                .map(|&value| i64::from(value)),
        );

        if let Some(type_ids) = type_ids.as_mut() {
            type_ids.extend(
                encoding
                    .get_type_ids()
                    .iter()
                    .map(|&value| i64::from(value)),
            );
        }
    }

    Ok(Tokenized {
        rows,
        cols,
        input_ids,
        attn_masks,
        type_ids,
    })
}

#[cfg(test)]
mod tests {
    use super::{parse_padding_mode_override, resolve_padding_strategy};
    use crate::model_config::PaddingMode;
    use tokenizers::PaddingStrategy;

    #[test]
    fn parse_padding_mode_override_accepts_expected_values() {
        assert_eq!(
            parse_padding_mode_override(Some("auto")).unwrap(),
            Some(PaddingMode::Auto)
        );
        assert_eq!(
            parse_padding_mode_override(Some("batch-longest")).unwrap(),
            Some(PaddingMode::BatchLongest)
        );
        assert_eq!(
            parse_padding_mode_override(Some("fixed")).unwrap(),
            Some(PaddingMode::Fixed)
        );
    }

    #[test]
    fn parse_padding_mode_override_rejects_invalid_values() {
        assert!(parse_padding_mode_override(Some("unknown")).is_err());
    }

    #[test]
    fn resolve_padding_strategy_uses_fixed_for_auto_when_model_has_fixed_padding() {
        match resolve_padding_strategy(PaddingMode::Auto, 64, Some(64)) {
            PaddingStrategy::Fixed(64) => {}
            other => panic!("expected Fixed(64), got {:?}", other),
        }
    }
}
