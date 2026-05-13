use gte::embedder::Embedder;
use gte::model_config::ModelLoadOverrides;

fn model_dir(env_var: &str) -> Option<String> {
    std::env::var(env_var).ok().filter(|v| !v.is_empty())
}

#[test]
fn test_e5_single_embedding_shape() {
    let Some(dir) = model_dir("GTE_BENCH_E5_DIR") else { return };
    let embedder = Embedder::from_dir(&dir, 0, 3, ModelLoadOverrides::default())
        .expect("embedder should initialize");
    let result = embedder
        .embed(vec!["query: Hello world".to_string()])
        .expect("embed should succeed");

    assert_eq!(result.shape()[0], 1);
    assert!(result.shape()[1] > 0);
}

#[test]
fn test_clip_single_embedding_shape() {
    let Some(dir) = model_dir("GTE_BENCH_CLIP_DIR") else { return };
    let embedder = Embedder::from_dir(&dir, 0, 3, ModelLoadOverrides::default())
        .expect("embedder should initialize");
    let result = embedder
        .embed(vec!["a photo of a cat".to_string()])
        .expect("embed should succeed");

    assert_eq!(result.shape()[0], 1);
    assert!(result.shape()[1] > 0);
}

#[test]
fn test_e5_batch_embedding_shape() {
    let Some(dir) = model_dir("GTE_BENCH_E5_DIR") else { return };
    let embedder = Embedder::from_dir(&dir, 0, 3, ModelLoadOverrides::default())
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
fn test_e5_long_input_truncation_no_error() {
    let Some(dir) = model_dir("GTE_BENCH_E5_DIR") else { return };
    let embedder = Embedder::from_dir(&dir, 0, 3, ModelLoadOverrides::default())
        .expect("embedder should initialize");
    let very_long_text = "word ".repeat(1000);
    let result = embedder
        .embed(vec![very_long_text])
        .expect("long input should be truncated without error");

    assert_eq!(result.shape()[0], 1);
    assert!(result.shape()[1] > 0);
}
