use criterion::{black_box, criterion_group, criterion_main, BenchmarkId, Criterion};
use gte::postprocess::{mean_pool, normalize_l2};
use ndarray::{Array2, Array3};

fn build_hidden_states(batch: usize, seq: usize, dim: usize) -> Array3<f32> {
    Array3::from_shape_fn((batch, seq, dim), |(b, s, d)| {
        (((b * 31 + s * 17 + d * 13) % 97) as f32) / 97.0
    })
}

fn build_attention_mask(batch: usize, seq: usize) -> Array2<i64> {
    Array2::from_shape_fn((batch, seq), |(_, s)| if s % 11 == 10 { 0 } else { 1 })
}

fn bench_mean_pool(c: &mut Criterion) {
    let mut group = c.benchmark_group("mean_pool");
    for (batch, seq, dim) in [(1, 32, 384), (8, 64, 384), (32, 64, 768)] {
        let hidden_states = build_hidden_states(batch, seq, dim);
        let attention_mask = build_attention_mask(batch, seq);
        group.bench_with_input(
            BenchmarkId::from_parameter(format!("{batch}x{seq}x{dim}")),
            &(batch, seq, dim),
            |b, _| {
                b.iter(|| {
                    mean_pool(
                        black_box(hidden_states.view()),
                        black_box(attention_mask.view()),
                    )
                    .unwrap()
                })
            },
        );
    }
    group.finish();
}

fn bench_normalize_l2(c: &mut Criterion) {
    let mut group = c.benchmark_group("normalize_l2");
    for (rows, dim) in [(1, 384), (8, 384), (32, 768), (128, 768)] {
        let embeddings = Array2::from_shape_fn((rows, dim), |(row, col)| {
            (((row * 19 + col * 7) % 113) as f32) / 113.0
        });
        group.bench_with_input(
            BenchmarkId::from_parameter(format!("{rows}x{dim}")),
            &(rows, dim),
            |b, _| b.iter(|| normalize_l2(black_box(embeddings.clone()))),
        );
    }
    group.finish();
}

criterion_group!(benches, bench_mean_pool, bench_normalize_l2);
criterion_main!(benches);
