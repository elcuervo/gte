use gte::model_config::PaddingMode;
use gte::tokenizer::Tokenizer;

#[test]
#[ignore = "requires ext/gte/tests/fixtures/e5/tokenizer.json"]
fn test_e5_tokenizer_output_shape() {
    const TOKENIZER: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/e5/tokenizer.json");

    let tokenizer =
        Tokenizer::new(TOKENIZER, 512, true, PaddingMode::BatchLongest, None).expect("tokenizer should load");
    let texts = vec!["Hello, world!".to_string(), "A second, longer sentence to test padding behavior.".to_string()];

    let tokenized = tokenizer.tokenize(&texts).expect("tokenize should succeed");

    assert_eq!(tokenized.input_ids.nrows(), 2, "batch size should be 2");
    assert!(tokenized.input_ids.ncols() > 0, "sequence length should be non-zero");
    assert_eq!(tokenized.input_ids.len(), tokenized.input_ids.nrows() * tokenized.input_ids.ncols());
    assert_eq!(tokenized.attn_masks.len(), tokenized.attn_masks.nrows() * tokenized.attn_masks.ncols());

    let type_ids = tokenized.type_ids.as_ref().expect("type_ids should exist");
    assert_eq!(type_ids.len(), type_ids.nrows() * type_ids.ncols());
}

#[test]
#[ignore = "requires ext/gte/tests/fixtures/e5/tokenizer.json"]
fn test_e5_truncation_at_max_length() {
    const TOKENIZER: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/e5/tokenizer.json");

    let tokenizer =
        Tokenizer::new(TOKENIZER, 16, false, PaddingMode::BatchLongest, None).expect("tokenizer should load");
    let long_text = "word ".repeat(200);
    let tokenized = tokenizer.tokenize(&[long_text]).expect("tokenize should not error on long input");

    assert_eq!(tokenized.input_ids.nrows(), 1);
    assert_eq!(tokenized.input_ids.ncols(), 16, "sequence length should be truncated to max_length");
}
