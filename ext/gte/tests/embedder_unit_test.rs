use gte::embedder::normalize_l2;
use ndarray::array;

#[test]
fn test_normalize_l2_basic() {
    let input = array![[3.0f32, 4.0], [1.0, 0.0]];
    let result = normalize_l2(input);

    let row0 = result.row(0);
    assert!((row0[0] - 0.6).abs() < 1e-6);
    assert!((row0[1] - 0.8).abs() < 1e-6);
}

#[test]
fn test_normalize_l2_zero_vector_unchanged() {
    let input = array![[0.0f32, 0.0, 0.0]];
    let result = normalize_l2(input);
    let row = result.row(0);
    assert!(row.iter().all(|&x| x == 0.0));
}

#[test]
fn test_normalize_l2_unit_norm() {
    let input = array![[1.0f32, 2.0, 3.0], [4.0, 5.0, 6.0]];
    let result = normalize_l2(input);

    for row in result.rows() {
        let norm: f32 = row.mapv(|x: f32| x * x).sum().sqrt();
        assert!((norm - 1.0).abs() < 1e-6);
    }
}

#[test]
fn test_normalize_l2_already_unit_unchanged() {
    let input = array![[1.0f32, 0.0, 0.0]];
    let result = normalize_l2(input.clone());
    let row = result.row(0);
    assert!((row[0] - 1.0).abs() < 1e-6 && row[1] == 0.0 && row[2] == 0.0);
}
