use gte::embedder::Embedder;

#[test]
#[ignore = "requires ext/gte/tests/fixtures/e5/tokenizer.json and model.onnx"]
fn test_e5_single_embedding_shape() {
    const DIR: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/e5");

    let embedder = Embedder::from_dir(DIR, 0, 3, None, None, None, None)
        .expect("embedder should initialize");
    let result = embedder
        .embed(vec!["query: Hello world".to_string()])
        .expect("embed should succeed");

    assert_eq!(result.shape()[0], 1);
    assert!(result.shape()[1] > 0);
}

#[test]
#[ignore = "requires ext/gte/tests/fixtures/clip/tokenizer.json and model.onnx"]
fn test_clip_single_embedding_shape() {
    const DIR: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/clip");

    let embedder = Embedder::from_dir(DIR, 0, 3, None, None, None, None)
        .expect("embedder should initialize");
    let result = embedder
        .embed(vec!["a photo of a cat".to_string()])
        .expect("embed should succeed");

    assert_eq!(result.shape()[0], 1);
    assert!(result.shape()[1] > 0);
}

#[test]
#[ignore = "requires ext/gte/tests/fixtures/e5/tokenizer.json and model.onnx"]
fn test_e5_batch_embedding_shape() {
    const DIR: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/e5");

    let embedder = Embedder::from_dir(DIR, 0, 3, None, None, None, None)
        .expect("embedder should initialize");
    let texts = vec![
        "query: first sentence".to_string(),
        "query: second sentence".to_string(),
        "query: third sentence for batch".to_string(),
    ];

    let result = embedder.embed(texts).expect("batch embed should succeed");

    assert_eq!(result.shape()[0], 3);
    assert!(result.shape()[1] > 0);
}

#[test]
#[ignore = "requires ext/gte/tests/fixtures/e5/tokenizer.json and model.onnx"]
fn test_e5_long_input_truncation_no_error() {
    const DIR: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/e5");

    let embedder = Embedder::from_dir(DIR, 0, 3, None, None, None, None)
        .expect("embedder should initialize");
    let very_long_text = "word ".repeat(1000);
    let result = embedder
        .embed(vec![very_long_text])
        .expect("long input should be truncated without error");

    assert_eq!(result.shape()[0], 1);
    assert!(result.shape()[1] > 0);
}
