use criterion::{black_box, criterion_group, criterion_main, BenchmarkId, Criterion};
use gte::embedder::Embedder;
use gte::model_config::ModelLoadOverrides;
use gte::postprocess::{mean_pool, normalize_l2};
use ndarray::{Array2, Array3};

fn build_hidden_states(batch: usize, seq: usize, dim: usize) -> Array3<f32> {
    Array3::from_shape_fn((batch, seq, dim), |(b, s, d)| (((b * 31 + s * 17 + d * 13) % 97) as f32) / 97.0)
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
            |b, _| b.iter(|| mean_pool(black_box(hidden_states.view()), black_box(attention_mask.view())).unwrap()),
        );
    }
    group.finish();
}

fn bench_normalize_l2(c: &mut Criterion) {
    let mut group = c.benchmark_group("normalize_l2");
    for (rows, dim) in [(1, 384), (8, 384), (32, 768), (128, 768)] {
        let embeddings = Array2::from_shape_fn((rows, dim), |(row, col)| (((row * 19 + col * 7) % 113) as f32) / 113.0);
        group.bench_with_input(BenchmarkId::from_parameter(format!("{rows}x{dim}")), &(rows, dim), |b, _| {
            b.iter(|| normalize_l2(black_box(embeddings.clone())))
        });
    }
    group.finish();
}

// Replicates the fixed-padding regression: a short input (4 tokens, like "cat")
// padded to max_length costs proportionally more in every downstream operation.
// Siglip2 regressed from 7ms → 44ms when tokenizer.json had "padding.strategy.Fixed: 64".
// Each row here represents: (label, actual_tokens, padded_to)
//   batch_longest → seq = actual_tokens
//   fixed         → seq = max_length regardless of input
fn bench_padding_impact(c: &mut Criterion) {
    let dim = 768;
    let mut group = c.benchmark_group("padding_impact");

    for (label, seq) in
        [("batch_longest/4tok", 4usize), ("fixed/siglip2_max_64", 64usize), ("fixed/e5_max_512", 512usize)]
    {
        let hidden_states = build_hidden_states(1, seq, dim);
        let attention_mask = build_attention_mask(1, seq);
        group.bench_with_input(BenchmarkId::from_parameter(label), &seq, |b, _| {
            b.iter(|| mean_pool(black_box(hidden_states.view()), black_box(attention_mask.view())).unwrap())
        });
    }
    group.finish();
}

// End-to-end inference bench. Requires real ONNX models on disk. Skips
// silently when env vars not set so default `cargo bench` stays cheap.
//   GTE_BENCH_E5_DIR       — sentence-transformers / E5-style text model dir
//   GTE_BENCH_SIGLIP2_DIR  — siglip2 text encoder dir
//   GTE_BENCH_CLIP_DIR     — clip text encoder dir
// Sweeps execution providers for quick local comparison.
fn bench_embedding_e2e(c: &mut Criterion) {
    let cases = [
        (
            "e5",
            "GTE_BENCH_E5_DIR",
            "query: cat",
            "query: ".to_string() + &"the quick brown fox jumps over the lazy dog ".repeat(20),
        ),
        ("siglip2", "GTE_BENCH_SIGLIP2_DIR", "cat", "a photo of ".to_string() + &"a cat sitting on a mat ".repeat(10)),
        ("clip", "GTE_BENCH_CLIP_DIR", "cat", "a photo of ".to_string() + &"a cat sitting on a mat ".repeat(10)),
    ];

    let mut group = c.benchmark_group("embedding_e2e");
    group.sample_size(20);

    for (model_label, env_var, short_input, long_input) in cases.iter() {
        let Some(dir) = std::env::var(env_var).ok().filter(|v| !v.is_empty()) else {
            continue;
        };

        for provider in ["cpu", "xnnpack"] {
            let overrides = ModelLoadOverrides { execution_providers: Some(provider), ..ModelLoadOverrides::default() };
            let embedder = match Embedder::from_dir(&dir, 3, overrides) {
                Ok(e) => e,
                Err(err) => {
                    eprintln!("skip {model_label} provider={provider}: {err}");
                    continue;
                }
            };

            for (input_label, input) in [("short", short_input.to_string()), ("long", long_input.clone())] {
                let id = BenchmarkId::from_parameter(format!("{model_label}/{provider}/{input_label}"));
                group.bench_with_input(id, &input, |b, text| {
                    b.iter(|| embedder.embed(black_box(&[text.clone()])).expect("embed succeeds"))
                });
            }
        }
    }
    group.finish();
}

criterion_group!(benches, bench_mean_pool, bench_normalize_l2, bench_padding_impact, bench_embedding_e2e);
criterion_main!(benches);
