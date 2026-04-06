# Common Pitfalls: Ruby+Rust ONNX Embedding Gem

**Domain:** Ruby gem with Rust cdylib extension for ONNX text embeddings
**Researched:** 2026-04-06
**Confidence:** HIGH (anchored in nero and gte-rs source) / MEDIUM (from training knowledge)

---

## 1. GVL (Global VM Lock) Not Released During Rust Inference

**Problem:** Ruby's GVL serializes all Ruby threads. If the Rust `embed()` call runs while holding the GVL, all other Ruby threads (Puma workers, background jobs) are blocked for the entire ORT inference duration. A 20ms embedding call → 20ms of full Ruby thread starvation.

**Warning signs:**
- Puma worker latency spikes correlating with embedding calls
- `bundle exec ruby -e "..."` with Thread.new blocks show serialized execution

**Prevention strategy:**
- In `magnus`, the GVL is automatically released when calling `function!` / `method!` bindings that don't use Ruby values during execution — verify this per magnus docs
- Alternatively: use `Ruby::thread_call_without_gvl` pattern explicitly around the ORT session run
- The ORT session `run()` call is pure C — it does not need the GVL

**Phase:** Scaffold / Ruby Bindings phase — test thread safety before shipping any version

---

## 2. ORT Session Thread Pool Over-subscription

**Problem:** ONNX Runtime creates its own internal thread pool (default: matches CPU core count). If multiple Puma threads each hold their own `ort::Session` instance, and each session uses N threads, you get N×threads threads competing — CPU thrashing, no throughput gain.

**Warning signs:**
- CPU usage doesn't increase when adding Puma threads
- `htop` shows many threads in context-switch overhead

**Prevention strategy:**
- Pass `inter_op_parallelism = 1` and `intra_op_parallelism = N` to session builder — single inter-op thread, N intra-op threads
- For serving use cases: consider a single `Session` shared across threads (ORT sessions are read-only at inference time, so sharing is safe)
- In `ort` v2 builder: `SessionBuilder::new(&environment)?.with_optimization_level(...)?.with_intra_threads(N)?`

**Phase:** Architecture validation / benchmarking phase

---

## 3. Panic Across FFI Boundary

**Problem:** A Rust `panic!` (from `unwrap()`, `expect()`, index out of bounds) crossing the FFI boundary into Ruby is undefined behavior — likely a SIGSEGV or interpreter crash, not a Ruby exception. nero's codebase propagates errors as `Result<_, magnus::Error>` — never `unwrap()` in magnus-exposed functions.

**Warning signs:**
- Ruby process crashes with `Segmentation fault` instead of raising `RuntimeError`
- Stack trace shows no Ruby frames, only native frames

**Prevention strategy:**
- Use `Result<T, magnus::Error>` return type on all `#[wrap]` methods
- Convert `ort::Error`, `tokenizers::Error`, and `std::io::Error` → `magnus::Error` via `.map_err(|e| magnus::Error::new(ruby.exception_runtime_error(), e.to_string()))`
- Define a `GTE::Error` Ruby exception class and raise it specifically
- Never use `unwrap()` in any function reachable from Ruby

**Evidence:** nero `ext/nero/src/lib.rs` — all functions return `Result<_, Error>`, explicit error module

**Phase:** Scaffold — establish error handling before any other Rust code

---

## 4. Tokenizer Thread Safety (`tokenizers::Tokenizer` is not `Send`)

**Problem:** `tokenizers::Tokenizer` may not implement `Send` (or may only be partially thread-safe). Storing a `Tokenizer` inside a `#[wrap]` struct that's shared across Ruby threads (e.g., via `@default` singleton) can cause data races.

**Warning signs:**
- Intermittent crashes or wrong tokenization results under concurrent load
- Rust compiler error: `Tokenizer cannot be sent between threads safely`

**Prevention strategy:**
- Use per-instance ownership (each `Embedder` Ruby object owns its tokenizer) — not a shared global
- If sharing is needed: wrap in `Arc<Mutex<Tokenizer>>` and hold the mutex only during tokenization
- The gte-rs pattern keeps the `Tokenizer` per-pipeline instance — follow this pattern

**Phase:** Rust core phase — validate thread safety before Ruby bindings

---

## 5. ONNX Model Input Tensor Name Mismatches

**Problem:** Different ONNX exports of the same model family may have different input/output tensor names. The gte-rs code assumes `"input_ids"`, `"attention_mask"`, `"last_hidden_state"` — a different export may use `"token_type_ids"` as required or optional, or output `"sentence_embedding"` instead.

**Warning signs:**
- ORT raises `Input name 'token_type_ids' not found in model` or similar
- Embeddings are all-zeros or NaN
- Shape mismatch errors on batch runs

**Prevention strategy:**
- Verify model tensor names with `onnx.load()` (Python) or ORT session metadata before implementing each preset
- For Siglip2: output tensor name is LOW confidence — must inspect actual ONNX export
- For CLIP: some exports require `position_ids`; others do not
- Make `output_id` and optional tensor flags configurable in `ModelConfig` so users can override defaults

**Phase:** Rust core phase — before implementing model-specific presets

---

## 6. Nix ORT Linking: Missing `ORT_LIB_LOCATION`

**Problem:** The `ort` crate's build script (`ort-sys/build.rs`) looks for ONNX Runtime via `ORT_STRATEGY` env var. If `ORT_STRATEGY=system` but `ORT_LIB_LOCATION` is not set, the build script may not find the Nix-managed `libonnxruntime`. Result: build fails with `could not find onnxruntime` or silently links the wrong version.

**Warning signs:**
- `cargo build` fails with `ort-sys` build script errors
- Link errors like `cannot find -lonnxruntime`
- Works in CI (ORT_STRATEGY=download) but fails in Nix dev shell

**Prevention strategy:**
- Set explicitly in `flake.nix` shell hook or env:
  ```nix
  ORT_STRATEGY = "system";
  ORT_LIB_LOCATION = "${pkgs.onnxruntime}";
  ```
- Use `pkg-config` as a fallback (nixpkgs `onnxruntime` may register a pkg-config entry)
- Test: `cargo build` clean from within `nix develop` before any other work

**Phase:** Scaffold / flake.nix setup — first thing to validate

---

## 7. Binary Gem: ONNX Runtime Shared Library Not Bundled

**Problem:** For binary gem distribution (`gem install gte --platform x86_64-linux`), the compiled `.so` must either bundle `libonnxruntime.so` or document the system dependency. If the shared library is not found at runtime, users get `dlopen: cannot load shared object` with no clear error.

**Warning signs:**
- Gem installs fine but `require 'gte'` fails at runtime
- `ldd lib/gte/gte.so` shows `libonnxruntime.so.1 => not found`

**Prevention strategy:**
- Use `ORT_STRATEGY=download` (static or shared bundle) during the cross-gem CI build — `ort` crate can download a platform-specific ORT binary and statically link it
- Or: document system ORT requirement clearly and bump to bundling strategy before public release
- For v1 (internal/private gem): document Nix shell requirement; bundling can come later

**Phase:** Packaging phase

---

## 8. Benchmarking Against `fastembed`: Process Warm-up Not Accounted For

**Problem:** ONNX Runtime takes time to warm up the session (memory mapping model weights, JIT compilation of execution plan). If the benchmark measures the first call, GTE will look slower than `fastembed` even if it's faster for subsequent calls. This would invalidate the performance claim.

**Warning signs:**
- First `embed()` call is 5-10x slower than subsequent calls
- Benchmark results vary widely between runs

**Prevention strategy:**
- Always warm up: run `embed(["warmup"])` × 3 before starting benchmark timer
- Measure throughput, not latency for first call
- Use `rspec-benchmark`'s `perform_faster_than` with `warmup: 5` iterations
- Benchmark with batch sizes representative of production use (1, 8, 32 texts)
- Ensure fastembed comparison uses the same warm-up methodology

**Phase:** Benchmark / validation phase

---

## 9. Mean Pooling Implementation Error (E5)

**Problem:** E5 requires attention-mask weighted mean pooling (not simple mean over all tokens). A naive mean across all token positions includes padding tokens, which dilutes the embedding and degrades retrieval quality significantly.

**Warning signs:**
- E5 embeddings are slightly different from Python sentence-transformers reference
- Retrieval quality tests show lower recall@k than expected
- Cosine similarity between `embed_query("X")` and `embed_passage("X")` is not close to 1.0

**Prevention strategy:**
- Implement attention-masked mean pooling: multiply hidden states by attention mask, sum, then divide by attention mask sum (not sequence length)
- Validate against Python sentence-transformers: `SentenceTransformer("intfloat/e5-small-v2").encode(["query: hello"])` — output should match within float32 precision
- gte-rs uses CLS token extraction (`Token(0)`) rather than mean pooling — verify if E5 v2 variants prefer CLS or mean pooling

**Phase:** Rust core phase — before Ruby bindings

---

## 10. `build.rs` VERSION File Path Assumption

**Problem:** nero's `build.rs` reads `VERSION` from `../../VERSION` (relative to `ext/nero/`). If the gem directory structure changes or the workspace root is different, this fails silently at build time or panics.

**Warning signs:**
- `cargo build` panics with `VERSION file not found`
- CI works but local build fails (different directory context)

**Prevention strategy:**
- Use `cargo:rerun-if-changed=../../VERSION` and test path resolution from `ext/gte/build.rs`
- Or use `env!("CARGO_MANIFEST_DIR")` to construct an absolute path to the VERSION file
- nero's exact pattern: `std::fs::read_to_string("../../VERSION")` — verify relative depth is correct for GTE's directory structure (`ext/gte/` → `../../VERSION`)

**Evidence:** nero `ext/nero/build.rs` — exact pattern; depth is two levels up from crate root to gem root

**Phase:** Scaffold phase — catch immediately

---

## Summary by Phase

| Phase | Pitfalls to Address |
|-------|---------------------|
| Scaffold | GVL release pattern, build.rs VERSION path, Nix ORT linking |
| Rust core | Panic-across-FFI error handling, tokenizer thread safety, tensor name mismatches, mean pooling correctness |
| Ruby bindings | GVL release (confirm in magnus), thread safety under concurrent load |
| Benchmark | Warm-up methodology, fair fastembed comparison |
| Packaging | Binary gem ORT bundling strategy |
