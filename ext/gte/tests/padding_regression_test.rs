use gte::model_config::PaddingMode;
use gte::tokenizer::Tokenizer;

const TOKENIZER: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/minimal/tokenizer.json");

const SHORT_INPUT: &str = "cat";
const MAX_LENGTH: usize = 64;

#[test]
fn auto_padding_uses_batch_longest_regardless_of_tokenizer_json() {
    let tokenizer = Tokenizer::new(TOKENIZER, MAX_LENGTH, false, PaddingMode::Auto, Some(MAX_LENGTH))
        .expect("tokenizer should load");

    let tokenized = tokenizer.tokenize(&[SHORT_INPUT.to_string()]).expect("tokenize should succeed");

    assert!(
        tokenized.input_ids.ncols() < MAX_LENGTH,
        "Auto padding should use batch_longest, got cols={} (expected < {}). \
         This is the Siglip2 regression: short queries were padded to max_length, \
         making inference ~6x slower.",
        tokenized.input_ids.ncols(),
        MAX_LENGTH
    );
}

#[test]
fn fixed_padding_mode_pads_to_max_length() {
    let tokenizer =
        Tokenizer::new(TOKENIZER, MAX_LENGTH, false, PaddingMode::Fixed, None).expect("tokenizer should load");

    let tokenized = tokenizer.tokenize(&[SHORT_INPUT.to_string()]).expect("tokenize should succeed");

    assert_eq!(tokenized.input_ids.ncols(), MAX_LENGTH, "Fixed mode should pad to max_length");
    assert_eq!(tokenized.input_ids.len(), MAX_LENGTH);
    assert_eq!(tokenized.attn_masks.len(), MAX_LENGTH);
}

#[test]
fn batch_longest_padding_uses_longest_sequence_in_batch() {
    let tokenizer =
        Tokenizer::new(TOKENIZER, MAX_LENGTH, false, PaddingMode::BatchLongest, None).expect("tokenizer should load");

    let tokenized =
        tokenizer.tokenize(&["cat".to_string(), "hello world".to_string()]).expect("tokenize should succeed");

    assert_eq!(tokenized.input_ids.nrows(), 2);
    assert!(
        tokenized.input_ids.ncols() < MAX_LENGTH,
        "BatchLongest should pad to longest in batch (2 tokens), not max_length ({}). Got cols={}",
        MAX_LENGTH,
        tokenized.input_ids.ncols()
    );
}

#[test]
fn auto_padding_with_no_fixed_hint_also_uses_batch_longest() {
    let tokenizer =
        Tokenizer::new(TOKENIZER, MAX_LENGTH, false, PaddingMode::Auto, None).expect("tokenizer should load");

    let tokenized = tokenizer.tokenize(&[SHORT_INPUT.to_string()]).expect("tokenize should succeed");

    assert!(tokenized.input_ids.ncols() < MAX_LENGTH);
}
