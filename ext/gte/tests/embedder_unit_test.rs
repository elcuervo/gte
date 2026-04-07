// ext/gte/tests/embedder_unit_test.rs
// Unit tests for embedder module additions — normalize_l2 and split tokenize/run methods.
// These tests do NOT require model fixtures (normalize_l2 is pure math).
// Run with: cargo test --no-default-features

use ndarray::array;
use gte::embedder::normalize_l2;

#[test]
fn test_normalize_l2_basic() {
    // Row [3.0, 4.0] has L2 norm = 5.0; normalized = [0.6, 0.8]
    let input = array![[3.0f32, 4.0], [1.0, 0.0]];
    let result = normalize_l2(input);

    let row0 = result.row(0);
    assert!(
        (row0[0] - 0.6).abs() < 1e-6,
        "normalized[0][0] should be ~0.6, got {}",
        row0[0]
    );
    assert!(
        (row0[1] - 0.8).abs() < 1e-6,
        "normalized[0][1] should be ~0.8, got {}",
        row0[1]
    );
}

#[test]
fn test_normalize_l2_zero_vector_unchanged() {
    // Zero vector must not become NaN — leave unchanged (norm == 0.0 guard)
    let input = array![[0.0f32, 0.0, 0.0]];
    let result = normalize_l2(input);
    let row = result.row(0);
    assert!(
        row.iter().all(|&x| x == 0.0),
        "zero vector must remain zero after normalize_l2"
    );
}

#[test]
fn test_normalize_l2_unit_norm() {
    // After normalization, each row's L2 norm must be ~1.0
    let input = array![[1.0f32, 2.0, 3.0], [4.0, 5.0, 6.0]];
    let result = normalize_l2(input);

    for row in result.rows() {
        let norm: f32 = row.mapv(|x: f32| x * x).sum().sqrt();
        assert!(
            (norm - 1.0).abs() < 1e-6,
            "row norm should be 1.0 after normalization, got {}",
            norm
        );
    }
}

#[test]
fn test_normalize_l2_already_unit_unchanged() {
    // A row that is already unit length should come out unchanged
    let input = array![[1.0f32, 0.0, 0.0]];
    let result = normalize_l2(input.clone());
    let row = result.row(0);
    assert!(
        (row[0] - 1.0).abs() < 1e-6 && row[1] == 0.0 && row[2] == 0.0,
        "already-unit row should be unchanged"
    );
}
