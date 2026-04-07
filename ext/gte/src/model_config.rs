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
/// Per D-03: plain struct with factory methods, not a trait.
#[derive(Debug, Clone)]
pub struct ModelConfig {
    /// Maximum token length — inputs are truncated here (RUST-05)
    pub max_length: usize,
    /// Name of the output tensor in the ONNX graph to extract embeddings from
    pub output_tensor: &'static str,
    /// How to extract the embedding vector from the output tensor
    pub mode: ExtractorMode,
    /// Whether the model expects a token_type_ids input tensor
    pub with_type_ids: bool,
}

impl ModelConfig {
    /// E5 model family defaults:
    /// - max_length: 512 tokens
    /// - output_tensor: "last_hidden_state" (rank-3: [batch, seq, dim])
    /// - mode: MeanPool — mean pooling over attention-masked tokens (matches sentence-transformers)
    /// - with_type_ids: true — E5 BERT-based models need token_type_ids
    pub fn e5() -> Self {
        Self {
            max_length: 512,
            output_tensor: "last_hidden_state",
            mode: ExtractorMode::MeanPool,
            with_type_ids: true,
        }
    }

    /// CLIP model family defaults:
    /// - max_length: 77 tokens (CLIP context window)
    /// - output_tensor: "text_embeds" (rank-2: [batch, dim], already pooled)
    /// - mode: Raw — output is already the final embedding
    /// - with_type_ids: false — CLIP does not use token_type_ids
    pub fn clip() -> Self {
        Self {
            max_length: 77,
            output_tensor: "text_embeds",
            mode: ExtractorMode::Raw,
            with_type_ids: false,
        }
    }

    /// Siglip2 model family defaults:
    /// - max_length: 64 tokens
    /// - output_tensor: "TODO" — LOW CONFIDENCE, must inspect actual Siglip2 ONNX model
    ///   before writing the integration test. Run:
    ///   `python -c "import onnx; m=onnx.load('model.onnx'); print([o.name for o in m.graph.output])"`
    /// - mode: Raw — likely already pooled (verify with model inspection)
    /// - with_type_ids: false
    pub fn siglip2() -> Self {
        Self {
            max_length: 64,
            output_tensor: "TODO_inspect_siglip2_onnx_output_tensor_name",
            mode: ExtractorMode::Raw,
            with_type_ids: false,
        }
    }
}
