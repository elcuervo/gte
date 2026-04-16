# gte
![](https://images.unsplash.com/photo-1551225183-94acb7d595b6?q=80&w=2274&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D)

`gte` is a Ruby gem with a Rust extension for fast text embeddings with ONNX Runtime.
Inspired by https://github.com/fbilhaut/gte-rs

## Quick Start

```ruby
require "gte"

model = GTE.config(ENV.fetch("GTE_MODEL_DIR"))

# String input => GTE::Tensor (1 row)
tensor = model.embed("query: hello world")
vector = tensor.row(0)

# [] with string => Array<Float> (single vector)
single = model["query: nearest coffee shop"]

# [] with array => GTE::Tensor (batch)
batch = model[["query: hello", "query: world"]]
```

## Embedding Config (`GTE.config`)

`GTE.config(model_dir)` builds (and caches) a `GTE::Model`.

```ruby
default_model = GTE.config(ENV.fetch("GTE_MODEL_DIR"))

raw_model = GTE.config(ENV.fetch("GTE_MODEL_DIR")) do |config|
  config.with(normalize: false)
end

full_throttle = GTE.config(ENV.fetch("GTE_MODEL_DIR")) do |config|
  config.with(threads: 0)
end

custom = GTE.config(ENV.fetch("GTE_MODEL_DIR")) do |config|
  config.with(
    output_tensor: "last_hidden_state",
    max_length: 256,
    optimization_level: 3
  )
end
```

Config fields and defaults:

- `model_dir`: absolute path to model directory
- `threads`: `3` (set `0` for ONNX Runtime full-throttle threadpool)
- `optimization_level`: `3`
- `model_name`: `nil`
- `normalize`: `true` (L2 normalization at Ruby-facing API)
- `output_tensor`: `nil` (auto-select output tensor)
- `max_length`: `nil` (uses tokenizer/model defaults)

Notes:

- Return a `Config::Text` from the block (for example, `config.with(...)`).
- Model instances are cached by full config key; different config values create different cached instances.

## Reranker

Use `GTE::Reranker.config(model_dir)` for cross-encoder reranking.

```ruby
reranker = GTE::Reranker.config(ENV.fetch("GTE_RERANK_DIR")) do |config|
  config.with(sigmoid: true, threads: 0)
end

query = "how to train a neural network?"
candidates = [
  "Backpropagation and gradient descent are core techniques.",
  "This recipe uses flour and eggs."
]

# Raw scores aligned with input order
scores = reranker.score(query, candidates)
# => [0.93, 0.07]

# Ranked output sorted by score desc
ranked = reranker.rerank(query: query, candidates: candidates)
# => [
#      { index: 0, score: 0.93, text: "Backpropagation and gradient descent are core techniques." },
#      { index: 1, score: 0.07, text: "This recipe uses flour and eggs." }
#    ]
```

Reranker config fields and defaults:

- `model_dir`: absolute path to model directory
- `threads`: `3`
- `optimization_level`: `3`
- `model_name`: `nil`
- `sigmoid`: `false` (set `true` if you want bounded [0,1] style scores)
- `output_tensor`: `nil`
- `max_length`: `nil`

## Runtime + Result Examples

Process-local reuse (recommended for Puma/web servers):

```ruby
EMBEDDER = GTE.config(ENV.fetch("GTE_MODEL_DIR"))

def embed_query(text)
  EMBEDDER[text] # Array<Float>
end
```

## Model Directory

A model directory must include `tokenizer.json` and one ONNX model, resolved in this order:

1. `onnx/text_model.onnx`
2. `text_model.onnx`
3. `onnx/model.onnx`
4. `model.onnx`

Input policy is text-only. Graphs requiring unsupported multimodal inputs (such as `pixel_values`) are intentionally rejected.

## Execution Providers

Default behavior is CPU fallback via ONNX Runtime's default provider (no explicit provider registration).

Configure providers with `GTE_EXECUTION_PROVIDERS` (comma-separated, case-insensitive).
Supported values:

- `cpu` or `none`: CPU fallback (skip explicit provider registration)
- `xnnpack`
- `coreml`

Examples:

```bash
export GTE_EXECUTION_PROVIDERS=cpu
export GTE_EXECUTION_PROVIDERS=xnnpack,coreml
```

Ruby per-instance override (takes precedence over `GTE_EXECUTION_PROVIDERS`):

```ruby
model = GTE.config(ENV.fetch("GTE_MODEL_DIR")) do |config|
  config.with(execution_providers: "cpu")
end
```

## Development

Run commands inside `nix develop` via Make targets:

```bash
make setup
make compile
make test
make lint
make ci
```

## Benchmark

The repo includes two benchmark paths:

```bash
make bench
nix develop -c bundle exec rake bench:pure_compare
nix develop -c bundle exec rake bench:matrix_sweep
nix develop -c bundle exec ruby bench/memory_probe.rb --compare-pure
```

For release tracking and regression detection, record a run entry in `RUNS.md`:

```bash
make bench-record
```
