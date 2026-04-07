use std::path::Path;
use ndarray::Array2;
use ort::session::Session;
use crate::error::Result;
use crate::model_config::ModelConfig;
use crate::tokenizer::{Tokenized, Tokenizer};
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
        let session = build_session(model_path, &config)?;
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

    /// Tokenize texts for use with `run()` — split from embed() so the GVL
    /// can be released between tokenization and inference (per D-01).
    pub fn tokenize(&self, texts: &[String]) -> crate::error::Result<Tokenized> {
        self.tokenizer.tokenize(texts.to_vec())
    }

    /// Run ONNX session on pre-tokenized inputs — this is the call wrapped in rb_thread_call_without_gvl.
    pub fn run(&self, tokenized: &Tokenized) -> crate::error::Result<Array2<f32>> {
        run_session(&self.session, tokenized, &self.config)
    }
}

/// L2-normalize each row of an embedding matrix in-place.
/// Per D-08: normalization happens in Rust before FFI return.
/// If a row's norm is 0.0, leave it unchanged (avoid NaN).
pub fn normalize_l2(mut embeddings: Array2<f32>) -> Array2<f32> {
    for mut row in embeddings.rows_mut() {
        let norm = row.mapv(|x| x * x).sum().sqrt();
        if norm > 0.0 {
            row /= norm;
        }
    }
    embeddings
}
