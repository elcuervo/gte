// Regression tests for the fixed-padding performance bug.
//
// Root cause: PaddingMode::Auto silently read "padding.strategy.Fixed: N" from
// tokenizer.json and applied it, padding every input to max_length tokens.
// A query like "cat" (1 token) was padded to 64 tokens for Siglip2, making
// inference ~6x slower (44ms vs 7ms measured on Heroku).
//
// These tests use tests/fixtures/minimal/tokenizer.json which has
// "padding.strategy.Fixed: 64" baked in — exactly the condition that triggered
// the regression in production models like Siglip2.

use gte::model_config::PaddingMode;
use gte::tokenizer::Tokenizer;

const TOKENIZER: &str = concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/tests/fixtures/minimal/tokenizer.json"
);

// Short input tokenizes to 1 token with this vocabulary.
const SHORT_INPUT: &str = "cat";
const MAX_LENGTH: usize = 64;

#[test]
fn auto_padding_uses_batch_longest_regardless_of_tokenizer_json() {
    // fixed_padding_length: Some(MAX_LENGTH) simulates what model_profile::read_tokenizer_profile
    // returns when tokenizer.json has "padding.strategy.Fixed: 64".
    let tokenizer = Tokenizer::new(TOKENIZER, MAX_LENGTH, false, PaddingMode::Auto, Some(MAX_LENGTH))
        .expect("tokenizer should load");

    let tokenized = tokenizer
        .tokenize(&[SHORT_INPUT.to_string()])
        .expect("tokenize should succeed");

    // Old behavior: cols == 64 (silently padded to max_length)
    // New behavior: cols == actual token count (1 for "cat")
    assert!(
        tokenized.cols < MAX_LENGTH,
        "Auto padding should use batch_longest, got cols={} (expected < {}). \
         This is the Siglip2 regression: short queries were padded to max_length, \
         making inference ~6x slower.",
        tokenized.cols,
        MAX_LENGTH
    );
}

#[test]
fn fixed_padding_mode_pads_to_max_length() {
    let tokenizer = Tokenizer::new(TOKENIZER, MAX_LENGTH, false, PaddingMode::Fixed, None)
        .expect("tokenizer should load");

    let tokenized = tokenizer
        .tokenize(&[SHORT_INPUT.to_string()])
        .expect("tokenize should succeed");

    assert_eq!(
        tokenized.cols, MAX_LENGTH,
        "Fixed mode should pad to max_length"
    );
    assert_eq!(tokenized.input_ids.len(), MAX_LENGTH);
    assert_eq!(tokenized.attn_masks.len(), MAX_LENGTH);
}

#[test]
fn batch_longest_padding_uses_longest_sequence_in_batch() {
    let tokenizer = Tokenizer::new(TOKENIZER, MAX_LENGTH, false, PaddingMode::BatchLongest, None)
        .expect("tokenizer should load");

    // "cat" = 1 token, "hello world" = 2 tokens — batch pads to 2, not 64
    let tokenized = tokenizer
        .tokenize(&["cat".to_string(), "hello world".to_string()])
        .expect("tokenize should succeed");

    assert_eq!(tokenized.rows, 2);
    assert!(
        tokenized.cols < MAX_LENGTH,
        "BatchLongest should pad to longest in batch (2 tokens), not max_length ({}). Got cols={}",
        MAX_LENGTH,
        tokenized.cols
    );
}

#[test]
fn auto_padding_with_no_fixed_hint_also_uses_batch_longest() {
    // Sanity check: Auto with fixed_padding_length=None also uses BatchLongest
    let tokenizer = Tokenizer::new(TOKENIZER, MAX_LENGTH, false, PaddingMode::Auto, None)
        .expect("tokenizer should load");

    let tokenized = tokenizer
        .tokenize(&[SHORT_INPUT.to_string()])
        .expect("tokenize should succeed");

    assert!(tokenized.cols < MAX_LENGTH);
}
