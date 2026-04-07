use std::path::Path;
use ndarray::Array2;
use ort::session::Session;
use crate::error::Result;
use crate::model_config::ModelConfig;
use crate::tokenizer::Tokenizer;
use crate::session::{build_session, run_session};

/// The main inference orchestrator for Phase 2.
/// Holds all initialized state: tokenizer, ORT session, model config.
/// Phase 3 will wrap this in a #[wrap] magnus struct for Ruby FFI.
pub struct Embedder {
    tokenizer: Tokenizer,
    session: Session,
    config: ModelConfig,
}

impl Embedder {
    /// Initialize the embedder from file paths and a model config.
    ///
    /// # Arguments
    /// - `tokenizer_path`: path to tokenizer.json
    /// - `model_path`: path to model.onnx
    /// - `config`: ModelConfig with max_length, output_tensor, mode, with_type_ids
    ///
    /// # Example
    /// ```no_run
    /// use gte::embedder::Embedder;
    /// use gte::model_config::ModelConfig;
    /// let config = ModelConfig::e5();
    /// let embedder = Embedder::new("path/to/tokenizer.json", "path/to/model.onnx", config)?;
    /// # Ok::<(), gte::error::GteError>(())
    /// ```
    pub fn new<P1, P2>(
        tokenizer_path: P1,
        model_path: P2,
        config: ModelConfig,
    ) -> Result<Self>
    where
        P1: AsRef<Path>,
        P2: AsRef<Path>,
    {
        let tokenizer = Tokenizer::new(
            tokenizer_path,
            config.max_length,
            config.with_type_ids,
        )?;
        let session = build_session(model_path)?;
        Ok(Self { tokenizer, session, config })
    }

    /// Tokenize a batch of strings and run the ONNX inference session.
    /// Returns a 2D array of shape [batch_size, embedding_dim].
    ///
    /// RUST-03: Embedding extraction mode is determined by self.config.mode.
    ///
    /// // L2 normalization is applied in Phase 3 (Ruby API layer)
    pub fn embed(&self, texts: Vec<String>) -> Result<Array2<f32>> {
        let tokenized = self.tokenizer.tokenize(texts)?;
        let embeddings = run_session(&self.session, &tokenized, &self.config)?;
        Ok(embeddings)
    }
}
