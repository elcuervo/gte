/// Extraction mode for pulling embeddings from ORT session output.
/// Per D-04: simple enum with match arms, no trait objects.
#[derive(Debug, Clone, Copy)]
pub enum ExtractorMode {
    /// Output tensor shape is [batch, seq, dim] — take token at `index` (0 = CLS token)
    Token(usize),
    /// Output tensor shape is [batch, seq, dim] — mean pool over non-padding tokens using attention mask
    MeanPool,
    /// Output tensor shape is [batch, dim] — use as-is (already pooled)
    Raw,
}

/// Per-model-family configuration that drives tokenization and embedding extraction.
/// Config parameters are passed from Ruby — no hardcoded factory methods in Rust.
#[derive(Debug, Clone)]
pub struct ModelConfig {
    /// Maximum token length — inputs are truncated here (RUST-05)
    pub max_length: usize,
    /// Name of the output tensor in the ONNX graph to extract embeddings from
    pub output_tensor: String,
    /// How to extract the embedding vector from the output tensor
    pub mode: ExtractorMode,
    /// Whether the model expects a token_type_ids input tensor
    pub with_type_ids: bool,
    /// Whether the model expects an attention_mask input tensor
    pub with_attention_mask: bool,
    /// Number of intra-op threads (0 = ORT auto-detects)
    pub num_threads: usize,
    /// Graph optimization level (0-3, default 3 = ORT_ENABLE_ALL)
    pub optimization_level: u8,
}
