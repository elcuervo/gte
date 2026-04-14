use crate::error::{GteError, Result};
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
            strategy: PaddingStrategy::BatchLongest,
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
