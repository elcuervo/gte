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

custom = GTE.config(ENV.fetch("GTE_MODEL_DIR")) do |config|
  config.with(
    output_tensor: "last_hidden_state",
    max_length: 256,
    padding: "batch_longest",
    optimization_level: 3
  )
end
```

Config fields and defaults:

- `model_dir`: absolute path to model directory
- `optimization_level`: `3`
- `model_name`: `nil`
- `normalize`: `true` (L2 normalization at Ruby-facing API)
- `output_tensor`: `nil` (auto-select output tensor)
- `max_length`: `nil` (uses tokenizer/model defaults)
- `padding`: `nil` (auto; accepts `auto`, `batch_longest`, `fixed`)
- `execution_providers`: `nil` (falls back to `GTE_EXECUTION_PROVIDERS` / CPU default)

Notes:

- Return a `Config::Text` from the block (for example, `config.with(...)`).
- Model instances are cached by full config key; different config values create different cached instances.

Common model presets:

```ruby
e5 = GTE.config(ENV.fetch("GTE_MODEL_DIR")) do |config|
  config.with(
    model_name: "model.onnx",
    output_tensor: "last_hidden_state",
    max_length: 512,
    execution_providers: "cpu"
  )
end

siglip2 = GTE.config(ENV.fetch("GTE_SIGLIP2_DIR")) do |config|
  config.with(
    model_name: "text_model_int8.onnx",
    output_tensor: "pooler_output",
    max_length: 64,
    execution_providers: "cpu"
  )
end

clip = GTE.config(ENV.fetch("GTE_CLIP_DIR")) do |config|
  config.with(
    output_tensor: "sentence_embedding",
    max_length: 512,
    execution_providers: "cpu"
  )
end
```

Picking a specific layer:

- Use `output_tensor:` to request a named model output.
- `last_hidden_state` gives token-level hidden states and is mean-pooled by `gte` when the tensor is rank 3.
- `pooler_output`, `sentence_embedding`, and similar 2D tensors are returned directly and then L2-normalized by default.
- If the requested tensor is not present in the model, `gte` raises an error instead of silently falling back.

Low-level embedder setup (without model cache):

```ruby
embedder = GTE::Embedder.config(ENV.fetch("GTE_MODEL_DIR")) do |config|
  config.with(execution_providers: "cpu")
end
```

## Reranker

Use `GTE::Reranker.config(model_dir)` for cross-encoder reranking.

```ruby
reranker = GTE::Reranker.config(ENV.fetch("GTE_RERANK_DIR")) do |config|
  config.with(sigmoid: true)
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
- `optimization_level`: `3`
- `model_name`: `nil`
- `sigmoid`: `false` (set `true` if you want bounded [0,1] style scores)
- `output_tensor`: `nil`
- `max_length`: `nil`
- `padding`: `nil` (auto; accepts `auto`, `batch_longest`, `fixed`)
- `execution_providers`: `nil`

Session pool sizing:

- `GTE_SESSION_POOL_CAP`: optional positive integer cap for internal ONNX session pool size.
- Unset by default; runtime uses available CPU parallelism.

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

The repo includes a shared multi-runtime benchmark harness:

```bash
make bench
nix develop -c bundle exec rake bench:pure_compare
nix develop -c bundle exec rake bench:matrix_sweep
nix develop -c bundle exec ruby bench/memory_probe.rb --compare-pure
```

- `make bench`: Puma-like single-request comparison at concurrency `16`
- `rake bench:pure_compare`: batch amortization comparison
- `rake bench:matrix_sweep`: GTE provider sweep using the shared result schema
- Optional Python comparisons use `bench/python_onnxruntime.py` and are skipped automatically if local dependencies are unavailable.

To run benchmark + append a `RUNS.md` entry + enforce goal checks:

```bash
make bench-record
```

`bench/runs_ledger.rb check` is goal-focused by default:

- Enforces the goal metric (`response_time_p95`) across every enabled competitor.
- Does not require current-version coverage in `RUNS.md` unless explicitly enabled.
