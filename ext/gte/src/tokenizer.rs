use std::path::Path;
use ndarray::Array2;
use tokenizers::{PaddingParams, PaddingStrategy, TruncationParams};
use crate::error::{GteError, Result};

/// Output of a batch tokenization — three parallel Array2<i64> tensors.
pub struct Tokenized {
    /// Token IDs for each sequence in the batch — shape: [batch, seq]
    pub input_ids: Array2<i64>,
    /// Attention mask (1 = real token, 0 = padding) — shape: [batch, seq]
    pub attn_masks: Array2<i64>,
    /// Token type IDs (segment IDs), present only when `with_type_ids` is true — shape: [batch, seq]
    pub type_ids: Option<Array2<i64>>,
}

/// Wraps a HuggingFace tokenizer loaded from a `tokenizer.json` file.
///
/// Configured once at construction time with:
/// - Truncation at `max_length` tokens (RUST-05)
/// - BatchLongest padding strategy (pads each batch to its longest sequence)
pub struct Tokenizer {
    tokenizer: tokenizers::Tokenizer,
    with_type_ids: bool,
}

impl Tokenizer {
    /// Load a tokenizer from a `tokenizer.json` file, configuring truncation and padding.
    ///
    /// - `tokenizer_path`: path to a `tokenizer.json` file (HuggingFace format)
    /// - `max_length`: truncate inputs to at most this many tokens (RUST-05)
    /// - `with_type_ids`: whether to produce `token_type_ids` tensors (required by E5/BERT)
    pub fn new<P: AsRef<Path>>(
        tokenizer_path: P,
        max_length: usize,
        with_type_ids: bool,
    ) -> Result<Self> {
        let mut tokenizer = tokenizers::Tokenizer::from_file(tokenizer_path)
            .map_err(|e| GteError::Tokenizer(e.to_string()))?;

        // Configure truncation — with_truncation returns Result; always propagate (Pitfall 4)
        let mut truncation = TruncationParams::default();
        truncation.max_length = max_length;
        tokenizer
            .with_truncation(Some(truncation))
            .map_err(|e| GteError::Tokenizer(e.to_string()))?;

        // Configure padding — with_padding is infallible, no ? needed
        let mut padding = PaddingParams::default();
        padding.strategy = PaddingStrategy::BatchLongest;
        tokenizer.with_padding(Some(padding));

        Ok(Self {
            tokenizer,
            with_type_ids,
        })
    }

    /// Tokenize a batch of strings, returning parallel Array2<i64> tensors.
    ///
    /// All sequences in the batch are padded to the length of the longest one
    /// (BatchLongest), and truncated to `max_length` if necessary.
    pub fn tokenize(&self, texts: Vec<String>) -> Result<Tokenized> {
        let encodings = self
            .tokenizer
            .encode_batch(texts, true)
            .map_err(|e| GteError::Tokenizer(e.to_string()))?;

        let max_tokens = encodings.first().map(|e| e.len()).unwrap_or(0);

        let mut input_ids = Array2::<i64>::zeros((0, max_tokens));
        let mut attn_masks = Array2::<i64>::zeros((0, max_tokens));
        let mut type_ids = self
            .with_type_ids
            .then(|| Array2::<i64>::zeros((0, max_tokens)));

        for enc in &encodings {
            let ids: Vec<i64> = enc.get_ids().iter().map(|&x| x as i64).collect();
            let masks: Vec<i64> = enc.get_attention_mask().iter().map(|&x| x as i64).collect();

            // push_row can only fail on shape mismatch, which is impossible here
            // because all rows have length `max_tokens` by construction (BatchLongest padding)
            input_ids.push_row(ndarray::ArrayView::from(&ids)).unwrap();
            attn_masks
                .push_row(ndarray::ArrayView::from(&masks))
                .unwrap();

            if let Some(ref mut t) = type_ids {
                let tids: Vec<i64> = enc.get_type_ids().iter().map(|&x| x as i64).collect();
                t.push_row(ndarray::ArrayView::from(&tids)).unwrap();
            }
        }

        Ok(Tokenized {
            input_ids,
            attn_masks,
            type_ids,
        })
    }
}
