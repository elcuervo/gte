// ext/gte/tests/inference_integration_test.rs
// Full pipeline integration tests — require model fixture files.
// Tests are #[ignore] by default (per D-05).
//
// To run: cargo test -- --ignored (from within nix develop)
// Fixture layout expected:
//   ext/gte/tests/fixtures/e5/tokenizer.json
//   ext/gte/tests/fixtures/e5/model.onnx
//   ext/gte/tests/fixtures/clip/tokenizer.json
//   ext/gte/tests/fixtures/clip/model.onnx
//
// Reference vectors: pre-compute with Python sentence-transformers, then fill in.
// For Siglip2: inspect model.onnx output tensor name first (see model_config.rs siglip2() TODO).

use gte::embedder::Embedder;
use gte::model_config::ModelConfig;

fn is_close(a: f32, b: f32, epsilon: f32) -> bool {
    (a - b).abs() <= epsilon
}

fn embeddings_match(actual: &[f32], expected: &[f32], epsilon: f32) -> bool {
    actual.len() == expected.len()
        && actual.iter().zip(expected).all(|(a, e)| is_close(*a, *e, epsilon))
}

#[test]
#[ignore = "requires ext/gte/tests/fixtures/e5/tokenizer.json and model.onnx"]
fn test_e5_single_embedding_shape_and_correctness() {
    const TOKENIZER: &str = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/tests/fixtures/e5/tokenizer.json"
    );
    const MODEL: &str = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/tests/fixtures/e5/model.onnx"
    );

    // Tolerance: 1e-4 for cross-runtime ORT vs Python comparison (RESEARCH.md open question 2)
    const EPSILON: f32 = 1e-4;

    // TODO: fill in first 8 dims from Python reference:
    // import torch
    // from sentence_transformers import SentenceTransformer
    // model = SentenceTransformer("intfloat/e5-small-v2")
    // emb = model.encode(["query: Hello world"], normalize_embeddings=False)
    // print(emb[0][:8].tolist())
    const EXPECTED_FIRST_8: [f32; 8] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]; // REPLACE

    let config = ModelConfig::e5();
    let embedder = Embedder::new(TOKENIZER, MODEL, config)
        .expect("Embedder should initialize from fixtures");

    let result = embedder
        .embed(vec!["query: Hello world".to_string()])
        .expect("embed should succeed");

    // Shape: [1, embedding_dim] — E5-small is 384-dim
    assert_eq!(result.shape()[0], 1, "batch size must be 1");
    assert!(result.shape()[1] > 0, "embedding dim must be non-zero");

    // Correctness: first 8 dims must match reference within tolerance
    // NOTE: Uncomment after filling in EXPECTED_FIRST_8 above
    // let row = result.row(0);
    // let actual_first_8: Vec<f32> = row.iter().take(8).copied().collect();
    // assert!(
    //     embeddings_match(&actual_first_8, &EXPECTED_FIRST_8, EPSILON),
    //     "E5 embedding mismatch. actual={:?} expected={:?}",
    //     actual_first_8, EXPECTED_FIRST_8
    // );
    let _ = (EPSILON, EXPECTED_FIRST_8, embeddings_match as fn(&[f32], &[f32], f32) -> bool);
}

#[test]
#[ignore = "requires ext/gte/tests/fixtures/clip/tokenizer.json and model.onnx"]
fn test_clip_single_embedding_shape() {
    const TOKENIZER: &str = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/tests/fixtures/clip/tokenizer.json"
    );
    const MODEL: &str = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/tests/fixtures/clip/model.onnx"
    );

    let config = ModelConfig::clip();
    let embedder = Embedder::new(TOKENIZER, MODEL, config)
        .expect("Embedder should initialize from fixtures");

    let result = embedder
        .embed(vec!["a photo of a cat".to_string()])
        .expect("embed should succeed");

    // Shape: [1, embedding_dim] — CLIP text encoder is 512-dim
    assert_eq!(result.shape()[0], 1, "batch size must be 1");
    assert!(result.shape()[1] > 0, "embedding dim must be non-zero");
}

#[test]
#[ignore = "requires ext/gte/tests/fixtures/e5/tokenizer.json and model.onnx"]
fn test_e5_batch_embedding_shape() {
    const TOKENIZER: &str = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/tests/fixtures/e5/tokenizer.json"
    );
    const MODEL: &str = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/tests/fixtures/e5/model.onnx"
    );

    let config = ModelConfig::e5();
    let embedder = Embedder::new(TOKENIZER, MODEL, config)
        .expect("Embedder should initialize from fixtures");

    let texts = vec![
        "query: first sentence".to_string(),
        "query: second sentence".to_string(),
        "query: third sentence for batch".to_string(),
    ];

    let result = embedder.embed(texts).expect("batch embed should succeed");

    assert_eq!(result.shape()[0], 3, "batch size must be 3");
    assert!(result.shape()[1] > 0, "embedding dim must be non-zero");
}

#[test]
#[ignore = "requires ext/gte/tests/fixtures/e5/tokenizer.json and model.onnx"]
fn test_e5_long_input_truncation_no_error() {
    // RUST-05: long inputs must be truncated without error
    const TOKENIZER: &str = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/tests/fixtures/e5/tokenizer.json"
    );
    const MODEL: &str = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/tests/fixtures/e5/model.onnx"
    );

    let config = ModelConfig::e5(); // max_length=512
    let embedder = Embedder::new(TOKENIZER, MODEL, config)
        .expect("Embedder should initialize from fixtures");

    // Generate input that exceeds 512 tokens — must not error
    let very_long_text = "word ".repeat(1000);
    let result = embedder
        .embed(vec![very_long_text])
        .expect("long input must be truncated silently, not error (RUST-05)");

    assert_eq!(result.shape()[0], 1, "batch size must be 1 even for truncated input");
    assert!(result.shape()[1] > 0, "embedding dim must be non-zero");
}
