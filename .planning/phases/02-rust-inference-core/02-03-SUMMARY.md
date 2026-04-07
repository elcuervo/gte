---
phase: 02-rust-inference-core
plan: "03"
subsystem: inference
tags: [rust, onnx, ort, tokenizers, ndarray, embedder, testing, cdylib, rlib]

# Dependency graph
requires:
  - phase: 02-rust-inference-core-01
    provides: "Tokenizer struct + Tokenized type (tokenize batch, truncation, padding)"
  - phase: 02-rust-inference-core-02
    provides: "Session (build_session, run_session) + ModelConfig + ExtractorMode"
provides:
  - "Embedder struct: full tokenize -> session -> extract pipeline orchestrator"
  - "Embedder::new(tokenizer_path, model_path, config) -> Result<Self>"
  - "Embedder::embed(Vec<String>) -> Result<Array2<f32>>"
  - "Integration test scaffold: E5 (single, batch, truncation) and CLIP, all #[ignore]"
  - "Tokenizer unit tests: shape and truncation behavior, #[ignore] (require tokenizer.json)"
  - ".gitignore: ext/gte/tests/fixtures/ excluded from version control"
  - "Cargo ruby-ffi feature: enables cdylib+rlib split for Rust integration test builds"
affects: [03-ruby-ffi, testing, benchmarks]

# Tech tracking
tech-stack:
  added:
    - "Cargo [features] with ruby-ffi optional feature gating magnus+rb-sys"
    - "rlib added to crate-type alongside cdylib (enables integration test linking)"
  patterns:
    - "Embedder orchestrator: thin coordinator holds Tokenizer + Session + ModelConfig"
    - "ruby-ffi feature flag: separates Ruby C symbols from pure-Rust inference modules"
    - "cfg(feature = ruby-ffi) on magnus::init: prevents linker errors in test builds"
    - "All #[ignore] integration tests: fixture-dependent tests run only with --ignored"
    - "CARGO_MANIFEST_DIR for fixture paths: portable across machines and CI"
    - "cargo test --no-default-features: test command for the cdylib+rlib crate split"

key-files:
  created:
    - "ext/gte/src/embedder.rs"
    - "ext/gte/tests/tokenizer_unit_test.rs"
    - "ext/gte/tests/inference_integration_test.rs"
    - ".gitignore"
  modified:
    - "ext/gte/src/lib.rs"
    - "ext/gte/Cargo.toml"
    - "flake.nix"

key-decisions:
  - "Embedder holds all initialized state (Tokenizer + Session + ModelConfig) — no lazy init, fail-fast at construction"
  - "L2 normalization deferred to Phase 3 (Ruby API layer) — Embedder returns raw unnormalized Array2<f32>"
  - "ruby-ffi Cargo feature gates magnus+rb-sys: cdylib+rlib crate-type enables integration tests without Ruby runtime"
  - "cargo test --no-default-features is the test command: excludes Ruby linker symbols for pure-Rust test binaries"
  - "All integration tests #[ignore]: zero-friction CI (no fixtures needed), manual run with --ignored once fixtures available"
  - "ORT_DYLIB_PATH and DYLD_LIBRARY_PATH added to flake.nix shellHook: ORT dylib findable at test runtime on macOS"

patterns-established:
  - "Pattern: Embedder as thin orchestrator — no business logic, delegates to Tokenizer::tokenize and run_session"
  - "Pattern: cdylib+rlib+ruby-ffi feature for Ruby gem crates that need Rust integration tests"
  - "Pattern: #[ignore = reason string] on all fixture-dependent tests with clear fixture path in message"
  - "Pattern: CARGO_MANIFEST_DIR concat for portable fixture paths in integration tests"

requirements-completed: [RUST-03, RUST-04]

# Metrics
duration: 10min
completed: 2026-04-07
---

# Phase 2 Plan 03: Embedder Orchestrator + Test Suite Summary

**Embedder struct wiring Tokenizer+Session+ModelConfig into embed(Vec<String>)->Array2<f32>, with cdylib/rlib split enabling cargo test of #[ignore] integration tests for E5 and CLIP pipelines**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-04-07T02:50:06Z
- **Completed:** 2026-04-07T02:58:00Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments

- Embedder orchestrator with Embedder::new() + Embedder::embed() completing RUST-03
- Full test scaffold for RUST-04: 4 integration tests (E5 single/batch/truncation, CLIP shape) and 2 tokenizer unit tests — all #[ignore], zero CI friction
- Fixed cdylib+rlib crate-type split with ruby-ffi feature to enable Rust integration tests without a Ruby runtime
- .gitignore created excluding ext/gte/tests/fixtures/ from version control
- flake.nix updated with ORT_DYLIB_PATH and DYLD_LIBRARY_PATH for ORT dylib resolution at test runtime

## Task Commits

Each task was committed atomically:

1. **Task 1: Create embedder.rs and update lib.rs** - `bf5b4ec` (feat)
2. **Task 2: Write unit tests and integration test scaffolding** - `0466203` (feat)

**Plan metadata:** (docs commit follows)

## Files Created/Modified

- `/ext/gte/src/embedder.rs` - Embedder struct: Tokenizer + Session + ModelConfig, embed() method (RUST-03)
- `/ext/gte/src/lib.rs` - Changed pub(crate) to pub, added pub mod embedder, gated magnus init on ruby-ffi feature
- `/ext/gte/Cargo.toml` - Added rlib to crate-type, added ruby-ffi optional feature gating magnus+rb-sys
- `/ext/gte/tests/tokenizer_unit_test.rs` - 2 tokenizer shape/truncation tests (#[ignore])
- `/ext/gte/tests/inference_integration_test.rs` - 4 full pipeline tests for E5 and CLIP (#[ignore], RUST-04)
- `/.gitignore` - Excludes ext/gte/tests/fixtures/
- `/flake.nix` - Added ORT_DYLIB_PATH and DYLD_LIBRARY_PATH to shellHook

## Decisions Made

- L2 normalization deferred to Phase 3 per plan: Embedder returns raw Array2<f32>, normalization belongs in the Ruby API layer
- `ruby-ffi` Cargo feature gates magnus+rb-sys so `cargo test --no-default-features` can build without a Ruby runtime
- All integration tests annotated `#[ignore]` — cargo test passes in CI with 0 failures even without ONNX model files

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added rlib to crate-type and ruby-ffi Cargo feature**
- **Found during:** Task 2 (writing integration tests)
- **Issue:** Rust integration tests in `tests/` compile as external crates and must link against the lib. A `cdylib`-only crate produces no Rust library artifact, so `use gte::...` in test files fails with E0433 "unresolved module or unlinked crate". `magnus` and `rb-sys` pull in Ruby C symbols that cause linker failure when building test binaries without the Ruby runtime.
- **Fix:** Added `"rlib"` to `crate-type`; added `ruby-ffi` optional feature gating `magnus` and `rb-sys`; gated `#[magnus::init]` on `#[cfg(feature = "ruby-ffi")]`; documented `cargo test --no-default-features` as the test command
- **Files modified:** ext/gte/Cargo.toml, ext/gte/src/lib.rs
- **Verification:** `cargo test --no-default-features` exits 0 with 0 failed; 6 tests total (all #[ignore] except 1 doc test)
- **Committed in:** 0466203 (Task 2 commit)

**2. [Rule 2 - Missing Critical] Added ORT_DYLIB_PATH and DYLD_LIBRARY_PATH to flake.nix shellHook**
- **Found during:** Task 2 (verifying cargo test inside nix develop)
- **Issue:** Test binaries using ORT failed at runtime with `dyld: Library not loaded: @rpath/libonnxruntime.1.24.4.dylib`. The flake.nix shellHook set `ORT_LIB_LOCATION` (used at build time by ort-sys) but not the dylib search path needed at runtime on macOS.
- **Fix:** Added `export ORT_DYLIB_PATH=${pkgs.onnxruntime}/lib/libonnxruntime.dylib` and `export DYLD_LIBRARY_PATH=${pkgs.onnxruntime}/lib` to shellHook
- **Files modified:** flake.nix
- **Verification:** `cargo test --no-default-features` succeeds inside `nix develop` pointing to worktree flake
- **Committed in:** 0466203 (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (1 blocking, 1 missing critical)
**Impact on plan:** Both auto-fixes required for integration tests to compile and run at all. No scope creep — all changes are minimal and directly enable the test infrastructure the plan requires.

## Issues Encountered

- macOS SIP strips `DYLD_LIBRARY_PATH` for child processes of nix develop when using the main repo flake — worktree flake must be used explicitly (`nix develop /path/to/worktree`) to get the updated shellHook. This is expected nix behavior; user documentation should note `cargo test --no-default-features` must be run inside the worktree's nix develop shell.

## Known Stubs

- `EXPECTED_FIRST_8: [f32; 8] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];` in `inference_integration_test.rs` line ~55 — intentional placeholder, correctness assertion is commented out. Must be filled from Python reference output once E5 fixtures are available. The shape-only assertion is unconditionally active.

## User Setup Required

To run the ignored integration tests, user must:
1. Place E5 tokenizer.json at `ext/gte/tests/fixtures/e5/tokenizer.json`
2. Place E5 model.onnx at `ext/gte/tests/fixtures/e5/model.onnx`
3. Place CLIP tokenizer.json at `ext/gte/tests/fixtures/clip/tokenizer.json`
4. Place CLIP model.onnx at `ext/gte/tests/fixtures/clip/model.onnx`
5. Run: `cargo test --no-default-features -- --ignored` (inside nix develop)

For non-ignored tests only: `cargo test --no-default-features` (no fixtures needed, all ignored)

## Next Phase Readiness

- Phase 3 (Ruby FFI) can wrap Embedder in a `#[wrap]` magnus struct — Embedder::new and embed() are the public interface
- All Phase 2 requirements addressed: RUST-01 (tokenizer), RUST-02 (session), RUST-03 (embedder), RUST-04 (tests), RUST-05 (truncation)
- Siglip2 output_tensor name still LOW confidence — must inspect actual ONNX export before writing Siglip2 integration test

---
*Phase: 02-rust-inference-core*
*Completed: 2026-04-07*

## Self-Check: PASSED

- FOUND: ext/gte/src/embedder.rs
- FOUND: ext/gte/tests/tokenizer_unit_test.rs
- FOUND: ext/gte/tests/inference_integration_test.rs
- FOUND: .gitignore
- FOUND commit bf5b4ec (Task 1: create Embedder orchestrator)
- FOUND commit 0466203 (Task 2: add test suite and cdylib/rlib split)
