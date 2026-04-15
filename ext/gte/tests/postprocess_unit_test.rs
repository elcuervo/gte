use gte::postprocess::sigmoid_scores;
use ndarray::array;

#[test]
fn test_sigmoid_scores_monotonic_and_bounded() {
    let mut scores = array![-10.0f32, -1.0, 0.0, 1.0, 10.0];
    sigmoid_scores(scores.view_mut());

    assert!(scores[0] < scores[1]);
    assert!(scores[1] < scores[2]);
    assert!(scores[2] < scores[3]);
    assert!(scores[3] < scores[4]);

    for score in scores.iter() {
        assert!((*score >= 0.0) && (*score <= 1.0));
    }
}
