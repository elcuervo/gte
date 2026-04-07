# Requirements

**Project:** GTE — Ruby gem with Rust cdylib extension for fast text embeddings
**Milestone:** v1 — Minimum implementation to validate embedding speed vs. fastembed
**Last updated:** 2026-04-06

---

## v1 Requirements

### Scaffold & Build

- [x] **SCAF-01**: Developer can enter reproducible dev environment via `nix develop` with Ruby 3.4, Rust, ONNX Runtime, and all build deps available
- [x] **SCAF-02**: Developer can run `bundle exec rake compile` and produce a native `.so`/`.bundle` extension
- [x] **SCAF-03**: Developer can run `require 'gte'` in Ruby without errors (extension loads)
- [x] **SCAF-04**: `GTE::Error` Ruby exception class exists and is raised for all Rust-level failures (no process crashes from panics crossing FFI)
- [x] **SCAF-05**: Gem version is synchronized between `VERSION` file and `Cargo.toml` (enforced via `build.rs` assertion)
- [x] **SCAF-06**: Multi-arch builds produce native gems for `aarch64-apple-darwin` and `x86_64-unknown-linux-gnu` via GitHub Actions CI

### Core Embedding (Rust)

- [x] **RUST-01**: Rust pipeline tokenizes a batch of strings using HuggingFace `tokenizers` crate loaded from a local `tokenizer.json` file
- [x] **RUST-02**: Rust pipeline runs an ONNX model session via `ort` v2 with correct input tensors (`input_ids`, `attention_mask`, and optional `token_type_ids`/`position_ids`)
- [x] **RUST-03**: Rust pipeline extracts embeddings from output tensor using configurable extraction mode (CLS token or Raw)
- [x] **RUST-04**: Rust pipeline is validated against real ONNX model files via Rust integration tests before Ruby bindings are added
- [x] **RUST-05**: Long inputs are truncated at model max token length (512 for E5, 77 for CLIP, 64 for Siglip2) without error

### Ruby Bindings

- [x] **BIND-01**: `GTE::Embedder.new(tokenizer_path:, model_path:, config:)` creates a Ruby object wrapping the Rust `#[wrap]` struct
- [x] **BIND-02**: `embedder.embed(texts)` accepts a Ruby `Array<String>` and returns `Array<Array<Float>>` (batch) or `Array<Float>` (single string)
- [x] **BIND-03**: The GVL (Global VM Lock) is released during the Rust inference call so concurrent Ruby threads are not blocked
- [x] **BIND-04**: All Rust errors are converted to `GTE::Error` Ruby exceptions — no segfaults or unhandled panics

### Ruby API Layer

- [x] **API-01**: `GTE::E5.new(model_path:)` instantiates an embedder with correct E5 defaults (`output_id: "last_hidden_state"`, CLS extraction, `token_type_ids: true`)
- [x] **API-02**: `GTE::CLIP.new(model_path:)` instantiates an embedder with correct CLIP defaults (`output_id: "text_embeds"`, Raw extraction, `token_type_ids: false`)
- [x] **API-03**: `GTE::Siglip2.new(model_path:)` instantiates an embedder with Siglip2 defaults (output tensor TBD from model inspection)
- [x] **API-04**: `GTE::E5#embed_query(text)` prepends `"query: "` prefix before embedding
- [x] **API-05**: `GTE::E5#embed_passage(text)` prepends `"passage: "` prefix before embedding
- [x] **API-06**: `GTE.configure { |c| c.model_path = "..." }` sets global defaults; `GTE.default` returns a memoized default embedder
- [x] **API-07**: Embedding output is L2-normalized by default (enables cosine similarity via dot product)

### Benchmark Validation

- [x] **BENCH-01**: Embedding throughput for E5-small exceeds `fastembed` gem on equivalent model, measured after warm-up (≥3 warmup iterations before timing)
- [x] **BENCH-02**: Benchmark covers batch sizes representative of production use: 1, 8, 32 texts

---

## v2 Requirements (Deferred)

- Image embeddings for CLIP and Siglip2 vision towers
- Model downloading from HuggingFace Hub
- Reranking / cross-encoder support
- GPU execution provider (CoreML, CUDA) configuration
- Streaming / async embedding calls
- Numo::NArray output format option
- Built-in chunking for oversized inputs
- Similarity search primitives (defer to `neighbor` gem)

---

## Out of Scope

- **Image embeddings (v1)** — adds pixel preprocessing pipeline complexity; validates after text works
- **Model downloading** — user provides local ONNX files + tokenizer.json; no HF Hub integration in v1
- **HTTP server / REST API** — library only; Rack/Rails integration is documented, not built
- **GPU execution providers** — CPU-only for benchmark validation; CoreML/CUDA deferred
- **Built-in similarity search** — `neighbor` gem handles this; GTE returns vectors
- **Reranking** — different pipeline (cross-encoder), different project scope

---

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| SCAF-01 | Phase 1 | Complete |
| SCAF-02 | Phase 1 | Complete |
| SCAF-03 | Phase 1 | Complete |
| SCAF-04 | Phase 1 | Complete |
| SCAF-05 | Phase 1 | Complete |
| SCAF-06 | Phase 1 | Complete |
| RUST-01 | Phase 2 | Complete |
| RUST-02 | Phase 2 | Complete |
| RUST-03 | Phase 2 | Complete |
| RUST-04 | Phase 2 | Complete |
| RUST-05 | Phase 2 | Complete |
| BIND-01 | Phase 3 | Complete |
| BIND-02 | Phase 3 | Complete |
| BIND-03 | Phase 3 | Complete |
| BIND-04 | Phase 3 | Complete |
| API-01 | Phase 3 | Complete |
| API-02 | Phase 3 | Complete |
| API-03 | Phase 3 | Complete |
| API-04 | Phase 3 | Complete |
| API-05 | Phase 3 | Complete |
| API-06 | Phase 3 | Complete |
| API-07 | Phase 3 | Complete |
| BENCH-01 | Phase 4 | Complete |
| BENCH-02 | Phase 4 | Complete |

---

## Requirement Quality Notes

All requirements are:
- **Specific and testable** — each maps to an observable behavior or passing test
- **Atomic** — one capability per requirement
- **User/developer-centric** — phrased as what a developer can do, not what the system does internally
