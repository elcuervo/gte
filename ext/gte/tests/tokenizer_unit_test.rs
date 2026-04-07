// ext/gte/tests/tokenizer_unit_test.rs
// Unit tests for tokenizer module — require tokenizer.json fixture but NO model files.
// Run with: cargo test -- --ignored (from within nix develop)

use gte::tokenizer::Tokenizer;

#[test]
#[ignore = "requires ext/gte/tests/fixtures/e5/tokenizer.json"]
fn test_e5_tokenizer_output_shape() {
    const TOKENIZER: &str = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/tests/fixtures/e5/tokenizer.json"
    );

    // E5 max_length = 512, with_type_ids = true
    let tokenizer = Tokenizer::new(TOKENIZER, 512, true)
        .expect("tokenizer should load from fixture");

    let texts = vec![
        "Hello, world!".to_string(),
        "A second, longer sentence to test padding behavior.".to_string(),
    ];

    let tokenized = tokenizer.tokenize(texts).expect("tokenize should succeed");

    // Both rows must have the same column count (BatchLongest padding)
    assert_eq!(
        tokenized.input_ids.shape()[0], 2,
        "batch size should be 2"
    );
    assert_eq!(
        tokenized.attn_masks.shape()[0], 2,
        "attention mask batch size should be 2"
    );
    assert_eq!(
        tokenized.input_ids.shape()[1], tokenized.attn_masks.shape()[1],
        "input_ids and attn_masks must have same sequence length (BatchLongest)"
    );
    assert!(
        tokenized.type_ids.is_some(),
        "E5 config with_type_ids=true should produce type_ids"
    );
}

#[test]
#[ignore = "requires ext/gte/tests/fixtures/e5/tokenizer.json"]
fn test_e5_truncation_at_max_length() {
    const TOKENIZER: &str = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/tests/fixtures/e5/tokenizer.json"
    );

    // Use max_length=16 to force truncation of a long input
    let tokenizer = Tokenizer::new(TOKENIZER, 16, false)
        .expect("tokenizer should load");

    // This generates far more than 16 tokens
    let long_text = "word ".repeat(200);
    let tokenized = tokenizer
        .tokenize(vec![long_text])
        .expect("tokenize should not error on long input");

    assert_eq!(
        tokenized.input_ids.shape()[1], 16,
        "sequence length must be truncated to max_length=16 (RUST-05)"
    );
}
