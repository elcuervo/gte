/// Rust-internal error type for the GTE inference pipeline.
/// Phase 3 will convert these into magnus::Error / GTE::Error (Ruby).
#[derive(Debug)]
pub enum GteError {
    /// Tokenizer initialization or encoding failure
    Tokenizer(String),
    /// ORT session creation or inference failure
    Inference(String),
    /// ORT library error (wrapped from ort::Error)
    Ort(String),
    /// Array dimensionality mismatch during embedding extraction
    Shape(String),
}

impl std::fmt::Display for GteError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            GteError::Tokenizer(msg) => write!(f, "GTE tokenizer error: {}", msg),
            GteError::Inference(msg) => write!(f, "GTE inference error: {}", msg),
            GteError::Ort(msg) => write!(f, "GTE ORT error: {}", msg),
            GteError::Shape(msg) => write!(f, "GTE shape error: {}", msg),
        }
    }
}

impl std::error::Error for GteError {}

impl From<ort::Error> for GteError {
    fn from(e: ort::Error) -> Self {
        GteError::Ort(e.to_string())
    }
}

impl From<ndarray::ShapeError> for GteError {
    fn from(e: ndarray::ShapeError) -> Self {
        GteError::Shape(e.to_string())
    }
}

/// Crate-level Result alias — use `crate::Result<T>` throughout the inference modules
pub type Result<T> = std::result::Result<T, GteError>;

#[cfg(feature = "ruby-ffi")]
impl From<GteError> for magnus::Error {
    fn from(e: GteError) -> Self {
        use magnus::prelude::*;
        let ruby = magnus::Ruby::get().expect("From<GteError> called from Ruby thread");
        // GTE::Error was defined in Phase 1 init() before any methods are registered.
        // define_module is idempotent — returns existing GTE module without re-defining it.
        let module = ruby
            .define_module("GTE")
            .expect("GTE module must exist");
        let gte_error_class = module
            .const_get::<_, magnus::ExceptionClass>("Error")
            .expect("GTE::Error must be defined before embedder methods are called");
        magnus::Error::new(gte_error_class, e.to_string())
    }
}
