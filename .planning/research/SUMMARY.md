# Project Research Summary

**Project:** GTE — Ruby gem with Rust cdylib extension for ONNX text embeddings
**Domain:** Native extension gem / ML inference library
**Researched:** 2026-04-06
**Confidence:** HIGH — anchored in two production reference implementations (`impl/nero`, `impl/gte-rs`)

## Executive Summary

GTE is a Ruby gem that exposes fast text embedding inference by delegating all computation to a Rust cdylib extension. The Rust layer owns tokenization (via HuggingFace `tokenizers`), ONNX graph execution (via `ort` v2), and tensor manipulation (via `ndarray`). Ruby handles configuration, API ergonomics, and type coercion only. This boundary is the entire architectural decision — no ML work happens in Ruby, no Ruby types cross into Rust beyond raw strings.

The recommended approach is a direct composition of two proven codebases: nero's gem scaffolding pattern (`magnus`, `rb-sys`, `extconf.rb`, `build.rs`, `flake.nix`, `oxidize-rb` CI actions) combined with gte-rs's inference pipeline (`ModelConfig`-parameterized `EmbedderInner`, `ExtractorMode`, `Tokenized` struct, `SessionInputs` assembly). Version pins are not optional — `ort = "=2.0.0-rc.9"` must be exact due to ABI sensitivity. The Nix dev shell must set `ORT_STRATEGY=system` and `ORT_LIB_LOCATION` explicitly; binary gem distribution requires `ORT_STRATEGY=download` (static linkage) in CI.

The primary risks are: (1) panics crossing the FFI boundary (crash Ruby process instead of raising a Ruby exception — must be addressed at scaffold time, before any other code), (2) GVL not released during inference (silently serializes Puma threads — validate early), and (3) tensor name mismatches between ONNX export variants (especially Siglip2 — output tensor name is not confirmed and must be inspected against an actual export before implementing that preset).

---

## Key Findings

### Recommended Stack

All version pins are directly observed from `impl/nero` and `impl/gte-rs` production code — not inferred.

**Core technologies:**
- `magnus = "0.8"` — Ruby-Rust FFI bindings; `#[wrap]`, `function!`, `method!`, `#[magnus::init]`; the only maintained option (rutie is dead)
- `rb-sys = "0.9"` with `stable-api-compiled-fallback` — generates ruby.h bindings for rake-compiler; bridges magnus to the build system
- `ort = "=2.0.0-rc.9"` (exact pin) — ONNX Runtime Rust bindings; pinned for ABI stability; proven against E5 inference in gte-rs
- `tokenizers = "0.21.0"` — HuggingFace tokenizers; loads `tokenizer.json`; handles BPE, WordPiece, SentencePiece; batched encode with padding
- `ndarray = "0.16.0"` — tensor construction and slicing; version-locked to ort's requirements
- `half = "2"` — F16/F32 conversion for FP16 model output tensors
- `oxidize-rb/actions/cross-gem` + `rb-sys-dock` — cross-compilation to Linux/ARM targets from GitHub Actions matrix
- Nix flake with `rust-overlay` — pinned Rust toolchain; `ORT_STRATEGY=system` dev shell; `ORT_STRATEGY=download` for gem packaging

**Do not use:** `rutie`, raw `rb-sys` for binding code, `tract`, global `OnceCell` singleton, Ruby `onnxruntime` or `tokenizers` gems, `orp` pipeline crate.

### Expected Features

**Must have (table stakes):**
- `embed(text)` single-string call returning `Array<Float>`
- `embed([text, ...])` batch call returning `Array<Array<Float>>`
- Model loaded from local filesystem path (tokenizer.json + onnx/ directory convention)
- Tokenization handled internally — users never touch token IDs
- Thread safety — GVL released during ORT inference
- Truncation at model's max token limit (512 for E5, 77 for CLIP, 64 for Siglip2)
- Meaningful Ruby exceptions from Rust errors (no process crashes on bad input)
- Deterministic output (ORT is deterministic by default)

**Should have (differentiators):**
- Model-family presets: `GTE::E5`, `GTE::CLIP`, `GTE::Siglip2` with correct defaults per family
- `embed_query` / `embed_passage` for E5 (task prefix injection before tokenization — required for retrieval quality)
- L2-normalized output option (enables cosine similarity via dot product; expected by `neighbor` gem)
- `configure` block + ENV fallback (`GTE_MODEL_PATH`) matching nero's 12-factor pattern
- Explicit ONNX variant selection (`model.onnx` vs `model_quantized.onnx`)
- `embed_documents` alias for langchainrb duck-type compatibility
- Throughput faster than `fastembed` gem (core benchmark claim)

**Defer to v2+:**
- Image embeddings (CLIP/Siglip2 vision tower) — pixel preprocessing pipeline, separate ONNX export
- Model downloading from HuggingFace Hub — caching, auth, version pinning complexity
- GPU execution provider configuration — build complexity; unnecessary for v1 benchmark
- Async/Ractor support — synchronous batch calls cover all use cases
- Built-in similarity search — delegate to `neighbor` gem
- Auto-chunking of oversized inputs — truncate and document; silent chunking surprises users

### Architecture Approach

The gem is a thin Ruby wrapper over a Rust cdylib. The Rust layer owns the entire inference pipeline: a single `Embedder` struct (magnus `#[wrap]`) holds an `ort::Session` and a `tokenizers::Tokenizer`, parameterized by a `ModelConfig` that carries `output_id`, `ExtractorMode` (Token/Raw), and boolean flags for optional inputs (`token_type_ids`, `position_ids`). This unified struct handles all three model families without per-family dispatch. Data flow: `Vec<String>` in, `Vec<Vec<f32>>` out — no ONNX/tokenizer types cross the FFI boundary. The Ruby layer adds ergonomics: class-level presets, a `configure` block, and the `@default` singleton pattern (implemented in Ruby, not Rust global state).

**Major components:**
1. `GTE` Ruby module — public API, `configure` block, `@default` instance accessor, class-level shortcut methods
2. `GTE::Embedder` Ruby class — wraps Rust struct, coerces input to `Vec<String>`, coerces output from `RArray` to `Array<Array<Float>>`
3. `GTE::Embedder` Rust `#[wrap]` struct — owns `ort::Session` + `tokenizers::Tokenizer` + `ModelConfig`; `rb_new` / `rb_embed` methods
4. `ModelConfig` Rust struct — carries `output_id`, `ExtractorMode`, `token_type_ids` flag, `position_ids` flag; drives all model-family behavior
5. `pipeline.rs` — tokenize → assemble `SessionInputs` → `session.run()` → extract by `output_id` → apply `ExtractorMode` → `Vec<Vec<f32>>`
6. Build system — `extconf.rb` (single-line `create_rust_makefile`), `build.rs` (VERSION sync assertion), Nix flake, GitHub Actions release matrix

### Critical Pitfalls

1. **Panic across FFI boundary** — never use `unwrap()` in any magnus-exposed function; all methods must return `Result<T, magnus::Error>`; define `GTE::Error` Ruby exception class at scaffold time before anything else
2. **GVL not released during inference** — validate that magnus releases GVL automatically on `function!`/`method!` bindings, or use `Ruby::thread_call_without_gvl` explicitly around `session.run()`; test with concurrent threads before shipping
3. **ORT session thread pool over-subscription** — set `inter_op_parallelism = 1` when multiple Embedder instances run concurrently in Puma; avoid CPU thrashing
4. **Nix ORT linking fails silently** — must set both `ORT_STRATEGY=system` and `ORT_LIB_LOCATION="${pkgs.onnxruntime}"` in flake.nix env; test `cargo build` from clean `nix develop` as the first scaffold validation
5. **Tensor name mismatches** — Siglip2 output tensor name is unconfirmed (LOW confidence); CLIP may or may not require `position_ids`; inspect actual ONNX exports with `onnx.load()` before implementing presets
6. **Binary gem: ORT not bundled** — use `ORT_STRATEGY=download` (static linkage) in cross-gem CI build; `ldd` output must not show `libonnxruntime.so => not found`
7. **Benchmark warm-up not accounted for** — always run 3+ warmup calls before measuring throughput; first ORT call is 5-10x slower due to session JIT; use same methodology for fastembed comparison
8. **E5 mean pooling vs CLS token** — gte-rs uses CLS token extraction (`Token(0)`), not attention-masked mean pooling; verify which E5 v2 variants prefer each, then validate against Python sentence-transformers reference output

---

## Implications for Roadmap

Based on component dependencies and pitfall phase assignments, five phases are the natural structure. Each phase must validate before the next begins — debugging pipeline errors from Rust unit tests is far easier than from a Ruby `RuntimeError` with no stack trace.

### Phase 1: Scaffold
**Rationale:** Everything else depends on a compiling cdylib skeleton with working ORT linkage. Pitfall 4 (Nix ORT linking) and Pitfall 1 (panic-across-FFI) must be resolved before any inference code exists.
**Delivers:** `nix develop` shell works, `cargo build` links against system ORT, `require 'gte'` loads without error, `GTE::Error` exception class defined
**Must establish:** Error handling pattern (`Result<_, magnus::Error>` on all exposed functions) before adding any other Rust code
**Addresses pitfalls:** Nix ORT linking (#6), `build.rs` VERSION path (#10), panic-across-FFI baseline (#3)

### Phase 2: Rust Inference Core (no Ruby bindings)
**Rationale:** Validate the full tokenize → session → extract pipeline against a real ONNX model file using Rust tests only. Tensor name mismatches and pooling errors are trivial to fix in `#[test]` and catastrophic to debug from Ruby.
**Delivers:** `pipeline.rs` runs E5 inference in a Rust integration test; output matches Python sentence-transformers reference within float32 tolerance
**Implements:** `ModelConfig`, `ExtractorMode`, `tokenizer.rs`, `pipeline.rs`
**Must verify before proceeding:** E5 pooling correctness (#9), Siglip2 tensor names (#5), tokenizer thread safety (#4)
**Research flag:** Inspect actual Siglip2 ONNX export to confirm `output_id` before implementing that preset

### Phase 3: Ruby Bindings
**Rationale:** Add the magnus `#[wrap]` layer only after the Rust pipeline is validated. GVL release must be confirmed in this phase.
**Delivers:** `GTE::Embedder.new(tokenizer_path, model_path, config)` and `embedder.embed(["text"])` callable from Ruby returning `Array<Array<Float>>`
**Implements:** `embedder.rs` with `rb_new`/`rb_embed`, `lib.rs` with `#[magnus::init]`
**Must validate:** GVL release under concurrent Ruby threads (#1); concurrent load test before merging

### Phase 4: Ruby API Layer
**Rationale:** Once the FFI boundary is correct, add the ergonomic Ruby layer. This is pure Ruby work — no Rust changes needed.
**Delivers:** `GTE::E5.new(model_path:)`, `embed_query`, `embed_passage`, `configure` block, `@default` singleton, langchainrb duck-type compatibility
**Implements:** `lib/gte/config.rb`, `lib/gte/embedder.rb` facade, `lib/gte.rb`
**Features delivered:** All table stakes + differentiators except benchmark validation

### Phase 5: Benchmark + Packaging
**Rationale:** Validate the core claim (faster than fastembed) with correct warm-up methodology, then package for distribution.
**Delivers:** `rspec-benchmark` suite proving throughput > fastembed at batch sizes 1/8/32; binary gem builds for `aarch64-apple-darwin`, `x86_64-linux`, `aarch64-linux`
**Must address:** Benchmark warm-up methodology (#8), ORT bundling in cross-gem CI (#7)
**Research flag:** Verify current fastembed gem architecture (subprocess vs FFI vs pure-Ruby ONNX) before benchmark design — this affects what "faster" means

### Phase Ordering Rationale

- Scaffold first because Nix ORT linking and panic-across-FFI are blocking for everything downstream
- Rust core before Ruby bindings because tensor errors are silent once wrapped in FFI — Rust tests give exact error messages
- Ruby API layer deferred until FFI is proven — avoids debugging Ruby `RuntimeError: (null)` with no context
- Benchmark last because it requires a complete, correct implementation to be meaningful

### Research Flags

Phases needing deeper investigation during planning:
- **Phase 2:** Inspect actual Siglip2 ONNX export — `output_id` and pooling strategy are LOW confidence; must confirm before writing pipeline code
- **Phase 5:** Verify fastembed gem architecture before designing benchmark — benchmark design depends on whether fastembed uses a subprocess, FFI, or pure-Ruby ONNX path

Phases with standard, well-documented patterns (skip research-phase):
- **Phase 1:** nero scaffold pattern is directly observable and known-working — copy, don't research
- **Phase 3:** magnus `#[wrap]` pattern is stable and documented; GVL release behavior is verifiable empirically
- **Phase 4:** Pure Ruby ergonomics — standard module/class design, no research needed

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All version pins directly observed in nero and gte-rs production code |
| Features | MEDIUM-HIGH | E5/CLIP well-documented; Siglip2 tensor names are LOW confidence |
| Architecture | HIGH | Component boundaries and data flow directly derived from gte-rs pipeline source |
| Pitfalls | HIGH (scaffold/core) / MEDIUM (benchmark) | Scaffold/FFI pitfalls confirmed from nero; benchmark numbers need real hardware validation |

**Overall confidence:** HIGH for build approach; one concrete gap (Siglip2 ONNX tensor names) needs resolution in Phase 2.

### Gaps to Address

- **Siglip2 output tensor name** — inspect actual HuggingFace ONNX export before Phase 2 implementation; do not assume `last_hidden_state` or `text_embeds`
- **CLIP `position_ids` requirement** — varies by ONNX export variant; confirm before writing preset
- **`ort` stable v2.0.0** — verify whether a non-rc release exists before finalizing pin; if stable is available, prefer it
- **fastembed gem architecture** — must understand whether it's subprocess/FFI/pure-Ruby before designing the benchmark comparison; affects what "faster" actually means
- **Nix `ORT_LIB_LOCATION` via pkg-config** — confirm whether nixpkgs `onnxruntime` auto-registers a pkg-config entry or requires explicit env var path

---

## Sources

### Primary (HIGH confidence)
- `impl/nero/ext/nero/Cargo.toml` — magnus 0.8, rb-sys 0.9 confirmed
- `impl/nero/ext/nero/src/lib.rs` — `#[wrap]`, `function!`, `method!`, `#[magnus::init]` pattern confirmed
- `impl/nero/ext/nero/extconf.rb` — `create_rust_makefile` single-line pattern confirmed
- `impl/nero/ext/nero/build.rs` — VERSION sync assertion pattern confirmed
- `impl/nero/.github/workflows/release.yml` — oxidize-rb matrix build, cargo-vendor confirmed
- `impl/nero/flake.nix` — Nix dev shell baseline confirmed
- `impl/gte-rs/Cargo.toml` — ort =2.0.0-rc.9, tokenizers 0.21.0, ndarray 0.16.0 confirmed
- `impl/gte-rs/src/tokenizer/mod.rs` — `encode_batch` API, `Tokenized` struct confirmed
- `impl/gte-rs/src/params/mod.rs` — `ModelConfig`/`Parameters` parameterization confirmed
- `impl/gte-rs/src/embed/output.rs` — `ExtractorMode` (Token vs Raw) confirmed
- `impl/gte-rs/src/commons/input/tensors.rs` — `SessionInputs` assembly, optional tensor names confirmed

### Secondary (MEDIUM confidence)
- Training knowledge — GVL release behavior with magnus `function!`/`method!` bindings
- Training knowledge — ORT session thread pool behavior under concurrent load
- Training knowledge — E5 task prefix requirements and pooling strategy

### Tertiary (LOW confidence — must validate)
- Siglip2 ONNX export output tensor name — must inspect actual export file
- CLIP `position_ids` requirement — varies by export; not directly observed
- fastembed gem internal architecture — unknown; affects benchmark design

---
*Research completed: 2026-04-06*
*Ready for roadmap: yes*
