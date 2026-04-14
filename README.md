# gte
![](https://images.unsplash.com/photo-1551225183-94acb7d595b6?q=80&w=2274&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D)

`gte` is a Ruby gem with a Rust extension for fast text embeddings with ONNX Runtime.
Inspired by https://github.com/fbilhaut/gte-rs

## Quick Start

```ruby
require "gte"

model = GTE.new(ENV.fetch("GTE_MODEL_DIR"))
vector = model["query: hello world"]

# Return raw (non-L2-normalized) vectors
raw_model = GTE.new(ENV.fetch("GTE_MODEL_DIR"), normalize: false)

# Override output tensor and tokenizer truncation length
custom_model = GTE.new(
  ENV.fetch("GTE_MODEL_DIR"),
  output_tensor: "pooled_sentence_embeddings_debiased_normalized",
  max_length: 512
)
```

For Puma or other thread pools, prefer process-local reuse:

```ruby
MODEL = GTE.new(ENV.fetch("GTE_MODEL_DIR"))
```

## Model Directory

A model directory must include `tokenizer.json` and one ONNX model, resolved in this order:

1. `onnx/text_model.onnx`
2. `text_model.onnx`
3. `onnx/model.onnx`
4. `model.onnx`

## Development

Run commands inside `nix develop`.

```bash
bundle exec rake compile
cargo test --manifest-path ext/gte/Cargo.toml --no-default-features
bundle exec rspec
```

## Benchmark

The repo includes two benchmark paths:

```bash
bundle exec rake bench:pure_compare
bundle exec rake bench:puma_compare
bundle exec rake bench:matrix_sweep
bundle exec ruby bench/memory_probe.rb --compare-pure
```

For release tracking and regression detection, record a run entry in `RUNS.md`:

```bash
bundle exec rake bench:record_run
```
