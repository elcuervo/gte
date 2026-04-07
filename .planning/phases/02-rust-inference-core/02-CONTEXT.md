# Phase 2: Rust Inference Core - Context

**Gathered:** 2026-04-06
**Status:** Ready for planning

<domain>
## Phase Boundary

Build the full tokenize → ONNX session → embedding extraction pipeline in Rust, validated with integration tests against real model files. No Ruby FFI yet — this phase proves the Rust inference core is correct before exposing it to Ruby.

Requirements in scope: RUST-01, RUST-02, RUST-03, RUST-04, RUST-05

</domain>

<decisions>
## Implementation Decisions

### Rust Source Organization
- **D-01:** Inference code lives in `ext/gte/src/` as flat modules (e.g., `tokenizer.rs`, `session.rs`, `model_config.rs`) — all inference stays in the single cdylib, no separate library crate
- **D-02:** Adapt gte-rs naming but drop `orp`/`composable` — direct ORT API calls (`SessionBuilder`, `Session::run`) without the pipeline abstraction layer; simpler and more readable for Phase 2
- **D-03:** ModelConfig is a shared trait or struct interface; three concrete types (`E5Config`, `ClipConfig`, `Siglip2Config`) each implementing/holding family-specific defaults (max token length, output extraction strategy)
- **D-04:** `ExtractorMode` is a simple enum `{ E5, Clip, Siglip2 }` with `match` arms for output tensor extraction — no trait objects, explicit and simple

### Integration Test Strategy
- **D-05:** ONNX model files and `tokenizer.json` live in a git-ignored `tests/fixtures/` directory; tests that require model files are annotated `#[ignore]` so `cargo test` passes without fixtures; CI skips them by default
- **D-06:** Embedding correctness validated by comparing against pre-computed reference vectors stored as inline constants in test code, within float32 tolerance (1e-5) — matches RUST-02 success criteria
- **D-07:** Both unit tests (tokenizer logic, no model files needed) AND integration tests (full pipeline, model files required) — unit tests give fast feedback; integration tests prove correctness
- **D-08:** Reference vectors stored as inline array constants in test functions — self-contained, no external fixture files for vectors

### Claude's Discretion
- Exact module file names and internal structure within each module
- How to configure ORT session (CPU provider, thread count, etc.) for tests
- Exact f32 tolerance value (1e-5 is a starting point; adjust if ORT produces slightly different results than Python)
- Whether to expose `ModelConfig` as a public or pub(crate) type in Phase 2 (Phase 3 will need it public)
- L2 normalization placement: in Rust inference core or deferred to Phase 3 (either is fine, but document the choice)

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `impl/gte-rs/src/tokenizer/mod.rs` — HuggingFace tokenizers API: `from_file`, `encode_batch`, padding/truncation setup; copy and adapt directly
- `impl/gte-rs/src/commons/input/tensors.rs` — ORT v2 tensor creation from ndarray; confirmed working pattern
- `impl/gte-rs/src/embed/` — Embedding extraction logic: which output tensor to use for E5 vs CLIP vs Siglip2; ExtractorMode concept
- `ext/gte/src/lib.rs` — Existing skeleton: `#[magnus::init]`, `GTE` module, `GTE::Error`, panic hook

### Established Patterns
- `Cargo.toml` already has `name = "gte"`, `crate-type = ["cdylib"]` — add `ort`, `tokenizers`, `ndarray`, `half` as dependencies (exact versions from STACK.md)
- gte-rs uses `ort = "=2.0.0-rc.9"` — pin this exact version (not a range)
- tokenizers API: `tokenizers::Tokenizer::from_file(path)` → `encode_batch(texts, add_special_tokens)` → `encoding.get_ids()` / `encoding.get_attention_mask()`
- ORT v2 session: `ort::session::Session::builder()?.commit_from_file(model_path)?` — NOT `SessionBuilder::new()` (v1 API)

### Integration Points
- Phase 3 will wrap these Rust types in `#[wrap]` magnus structs — keep inference struct fields accessible (not all private)
- `GTE::Error` already defined in `lib.rs`; Phase 2 error propagation should use Rust `Result` types that Phase 3 will convert to `GTE::Error`
- The `#[magnus::init]` function in `lib.rs` is NOT where inference code goes — it's purely the Ruby extension entry point; Phase 2 code goes in separate `src/` modules

</code_context>

<specifics>
## Specific Ideas

- Reference implementation at `impl/gte-rs/` is the canonical source for tokenizer and ORT API usage — read it before writing any Rust code
- The three model families differ in: max token length (E5=512, CLIP=77, Siglip2=64), output tensor name, whether to mean-pool or take CLS token, and normalization
- Phase 2 does NOT expose anything to Ruby — pure Rust, pure `cargo test`

</specifics>

<deferred>
## Deferred Ideas

- GVL release during `session.run` — Phase 3 concern (Ruby threading boundary)
- L2 normalization in the Ruby API layer — could live here or in Phase 3; defer decision to planning
- Model downloading / management — out of scope for v1 (user provides paths)

</deferred>

---

*Phase: 02-rust-inference-core*
*Context gathered: 2026-04-06*
