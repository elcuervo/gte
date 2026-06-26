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

# Binary f32 bytes (zero-copy to Numo/NumPy)
bytes = model.embed_binary("query: hello world")
```

## Embedding Config (`GTE::Pool`)

`GTE.config(model_dir)` creates a new pool with one ONNX session by default.

```ruby
default = GTE.config(ENV.fetch("GTE_MODEL_DIR"))
default.embed("query: hello world")

# With config overrides
configurable = GTE.config(ENV.fetch("GTE_MODEL_DIR")) do |config|
  config.with(
    output_tensor: "last_hidden_state",
    max_length: 128,
    execution_providers: "xnnpack"
  )
end

# Explicit pool size (each session costs ~120MB RSS)
large = GTE.config(ENV.fetch("GTE_MODEL_DIR"), pool_size: 4)
```

Config fields and defaults:

- `model_dir`: absolute path to model directory
- `optimization_level`: `3`
- `model_name`: `nil`
- `output_tensor`: `nil` (auto-select output tensor)
- `max_length`: `nil` (uses tokenizer/model defaults)
- `padding`: `nil` (auto; accepts `auto`, `batch_longest`, `fixed`)
- `execution_providers`: `nil` (falls back to `GTE_EXECUTION_PROVIDERS` / CPU default)

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

Output selection:

- Use `output_tensor:` to request a named model output.
- `last_hidden_state` gives token-level hidden states and is mean-pooled by `gte` when the tensor is rank 3.
- `pooler_output`, `sentence_embedding`, and similar 2D tensors are returned directly and L2-normalized.
- If the output tensor name suggests already-normalized output (e.g. `l2_norm`, `normalized`), normalization is skipped.
- If the requested tensor is not present in the model, `gte` raises an error instead of silently falling back.

Low-level embedder setup (without Pool convenience):

```ruby
embedder = GTE::Embedder.from_config(
  GTE::Embedder.default_config(ENV.fetch("GTE_MODEL_DIR"))
)
```

## Reranker

Use `GTE::Reranker.new(model_dir)` for cross-encoder reranking.

```ruby
reranker = GTE::Reranker.new(ENV.fetch("GTE_RERANK_DIR")) do |config|
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

gte uses a **pre-allocated session pool** per worker — it creates N sessions at
construction time, where N is determined by:

| Priority | Source | Description |
|----------|--------|-------------|
| 1 | `GTE_SESSION_POOL_SIZE` | Explicit size (e.g. `4`) |
| 2 | `PUMA_MAX_THREADS` | Match Puma concurrency (capped at 8) |
| 3 | Default | `1` (single session, matching the unsplash-api singleton pattern) |

The pool is fixed-size: sessions are never created or destroyed after construction.
When all sessions are busy, the calling thread blocks on `parking_lot::Mutex`
until a session is released. This avoids the allocation and memory overhead of
lazy-growing pools while matching the concurrency needs of application threads.

### Session Pre-Warming

The pool is pre-warmed automatically in `GTE.config` — one inference per
session is run on construction so the first production request never hits a cold
cache. No manual warmup step needed.

To re-warm (useful after fork in Puma's `on_worker_boot`):

```ruby
pool.warmup
```

### Tuning Performance

| Variable | Effect | Default |
|----------|--------|---------|
| `GTE_SESSION_POOL_SIZE` | Max ONNX sessions per worker | `1` (or `PUMA_MAX_THREADS`) |
| `GTE_INTRA_OP_NUM_THREADS` | Threads ONNX Runtime uses per inference op | `min(CPU cores, 4)` |
| `GTE_INTER_OP_NUM_THREADS` | Threads for independent graph nodes (irrelevant for text models) | `1` |
| `GTE_EXECUTION_PROVIDERS` | Comma-separated: `xnnpack`, `coreml`, `cpu` | Auto: `xnnpack` on arm64 |

**To squeeze more throughput:**
- Set `GTE_SESSION_POOL_SIZE` to match or slightly exceed your Puma `MAX_THREADS`.
- On machines with many cores, reduce `GTE_INTRA_OP_NUM_THREADS` to `1` or `2`
  to avoid CPU oversubscription when multiple sessions run concurrently.

**Memory estimation per worker:**
- Pool size N (default 1): **N × model file size × 3–5**
- Each additional session adds ~120MB RSS on arm64 with XNNPACK.

## Runtime

Process-local reuse (recommended for Puma/web servers):

```ruby
$gte = GTE.config(ENV.fetch("GTE_MODEL_DIR"))

def embed_query(text)
  $gte.embed(text).row(0) # Array<Float>
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
Docker wrk with random 135-text query set, 15s runs.

### In-Process Benchmarks

```bash
make bench
nix develop -c bundle exec ruby bench/memory_probe.rb --compare-pure
```

- `make bench`: Puma-like single-request comparison at concurrency `16`
- Optional Python comparisons use `bench/python_onnxruntime.py` and are skipped automatically if local dependencies are unavailable.

To run benchmark + append a `RUNS.md` entry + enforce goal checks:

```bash
make bench-record
```

`bench/runs_ledger.rb check` is goal-focused by default:

- Enforces the goal metric (`response_time_p95`) across every enabled competitor.
- Does not require current-version coverage in `RUNS.md` unless explicitly enabled.

## Fork Safety

GTE uses ONNX Runtime sessions which maintain internal thread pools for parallelism
(`GTE_INTRA_OP_NUM_THREADS`, default `min(cpus, 4)`). These thread pools are
per-session and may not survive `fork()` on some platforms.

**With Puma's `preload_app!`:**

Sessions built before `fork()` share memory via COW, but the internal ORT threads
created during `Session::builder().commit_from_file()` do not exist in the child
process. When a forked worker calls `session.run()`, ORT must recreate these
threads, which adds latency to the first inference call.

**Recommendations:**

1. **Set `GTE_INTRA_OP_NUM_THREADS=1`** in forked environments to avoid creating
   per-session thread pools entirely. ORT will run inference single-threaded,
   which is acceptable when multiple sessions handle concurrency.
2. **Build sessions in `on_worker_boot`** instead of before fork to guarantee
   fresh thread pools in each worker. This adds ~200ms to worker startup per
   model but ensures consistent inference latency:

   ```ruby
   # config/puma.rb
   on_worker_boot do
     $gte_pool = GTE.config(ENV.fetch("GTE_MODEL_DIR"))
   end
   ```

3. **If using `preload_app!`**, call `GTE.config` in `before_fork` and set
   `GTE_INTRA_OP_NUM_THREADS=1` to avoid thread pool issues in child processes.
