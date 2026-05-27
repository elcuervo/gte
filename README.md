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
- `GTE.warmup(model, threads:)` pre-grows the lazy session pool to its auto cap.
  Useful at boot in multi-threaded servers (Puma, Sidekiq) to avoid ~100-500ms cold-start latency.

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
    model_name: "text_model.onnx",
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

## Automatic Tuning

`gte` automatically adapts to the hardware — no configuration required.

### Execution Providers

`gte` automatically tries XNNPACK for optimized CPU inference. Falls back to
ORT's default CPU provider if unavailable.

- **ARM64** (Apple Silicon, AWS Graviton): XNNPACK is typically **~25% faster**
  than plain CPU while producing identical embeddings (cos=1.0, max_abs=0.0).
- **x86/x64** (Intel, AMD): XNNPACK offers minimal benefit — ORT's default CPU
  provider already uses MKL-DNN/oneDNN, which are better tuned for these chips.
  The auto-detect silently falls back to the default provider.

Configure providers explicitly with `GTE_EXECUTION_PROVIDERS` (comma-separated):

```bash
export GTE_EXECUTION_PROVIDERS=xnnpack,coreml
```

Set `cpu` or `none` to skip auto-detect and use ORT's default CPU provider.

### Session Pool

gte uses a **lazy session pool** per worker — it starts with 1 ONNX session
(same memory as pure Ruby's `OnnxRuntime::Model`) and only creates additional
sessions when all existing ones are busy, up to a cap:

| Priority | Source | Description |
|----------|--------|-------------|
| 1 | `GTE_SESSION_POOL_SIZE` | Explicit cap (e.g. `4`) |
| 2 | Auto | `min(MAX_THREADS, CPU cores)`, clamped to `[2, 4]` |

Example: Puma with `MAX_THREADS=5` on a 4-core machine → auto cap = 4.
Sessions beyond the initial one are created on-demand and never freed,
so peak memory is `cap × model_size` per worker.

### Session Pre-Warming

The lazy pool means the first concurrent requests pay a one-time cost
(~100–500 ms) while new sessions are built.  Eliminate this at boot
with a concurrent warmup matching your thread count:

```ruby
# In config/initializers or Puma on_worker_boot:
model = GTE.config(ENV.fetch("GTE_MODEL_DIR"))
GTE.warmup(model, threads: ENV.fetch("MAX_THREADS", "5").to_i)
```

The warmup sends `threads` concurrent requests, forcing the pool to
grow to its auto cap before production traffic arrives.

### Tuning Performance

| Variable | Effect | Default |
|----------|--------|---------|
| `GTE_SESSION_POOL_SIZE` | Max ONNX sessions per worker | Auto: `min(MAX_THREADS, CPU)`.clamp(2, 4) |
| `GTE_INTRA_OP_NUM_THREADS` | Threads ONNX Runtime uses per inference op | `min(CPU cores, 4)` |
| `GTE_INTER_OP_NUM_THREADS` | Threads for independent graph nodes (irrelevant for text models) | `1` |
| `GTE_EXECUTION_PROVIDERS` | Comma-separated: `xnnpack`, `coreml`, `cpu` | Auto: `xnnpack` on arm64 |
| `GTE.warmup(model, threads: N)` | Pre-grow session pool at boot | Not called by default |

**To squeeze more throughput:**
- Set `GTE_SESSION_POOL_SIZE` to match or slightly exceed your Puma `MAX_THREADS`.
- On machines with many cores, reduce `GTE_INTRA_OP_NUM_THREADS` to `1` or `2`
  to avoid CPU oversubscription when multiple sessions run concurrently.
- Call `GTE.warmup` at boot so the first request is never cold.

**Memory estimation per worker:**
- Pure Ruby: 1 `OnnxRuntime::Model` ≈ model file size × 3–5
- gte idle: 1 session ≈ same as pure Ruby
- gte peak: auto cap sessions ≈ cap × pure Ruby
- With auto cap=4: **at most 4× pure Ruby memory**, typical in practice is 1–2×

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


## Development

Run commands inside `nix develop` via Make targets:

```bash
make setup
make compile
make test
make lint
make ci
```

## Benchmarks

### Docker Rails+Puma+wrk (Real-World HTTP)

The `bench/rails/` directory contains a full-stack benchmark: Rails 7.1 API app served by Puma,
loaded with wrk (randomized text queries, 135 diverse texts).

Run for all models:

```bash
make bench-docker-compare
```

Run for a single model:

```bash
make bench-docker-sweep-siglip2
make bench-docker-validate  # cross-validation checks
```

#### Siglip2 (768-dim, pooler_output)

| Concurrency | GTE p90 | Pure Ruby p90 | Ratio | GTE RPS | Pure Ruby RPS |
|------------|---------|---------------|-------|---------|---------------|
| c=1 | ~14ms | ~92ms | 6.4× | ~89 | ~21 |
| c=2 | ~15ms | ~175ms | 11.4× | ~163 | ~21 |
| c=4 | ~39ms | ~293ms | 7.4× | ~219 | ~24 |
| c=8 | ~75ms | ~502ms | 6.7× | ~195 | ~24 |
| c=16 | ~279ms | ~606ms | 2.2× | ~219 | ~26 |

#### E5 (384-dim, last_hidden_state + mean pool)

| Concurrency | GTE p90 | Pure Ruby p90 | Ratio | GTE RPS | Pure Ruby RPS |
|------------|---------|---------------|-------|---------|---------------|
| c=1 | ~8ms | ~73ms | 9.3× | ~152 | ~32 |
| c=2 | ~8ms | ~95ms | 11.8× | ~291 | ~36 |
| c=4 | ~22ms | ~163ms | 7.5× | ~432 | ~45 |
| c=8 | ~51ms | ~291ms | 5.7× | ~451 | ~43 |
| c=16 | ~133ms | ~1080ms | 8.1× | ~467 | ~47 |

GTE releases the GVL during ONNX inference, enabling true parallelism across
Puma threads and worker processes. Pure Ruby is serialized
(~25–45 RPS regardless of concurrency).

Config: Puma workers=2, threads=min=2/max=5, cpus=4, mem_limit=3g.
GTE session pool auto cap=4 (min(MAX_THREADS=5, 10 cores) → clamp → 4).
Docker wrk with random 135-text query set, 15s runs.

### In-Process Benchmarks

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
