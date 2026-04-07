---
phase: 02-rust-inference-core
plan: "02"
subsystem: rust-inference
tags: [rust, ort, tokenizers, ndarray, onnx, huggingface, array2, session]

# Dependency graph
requires:
  - phase: 02-rust-inference-core-01
    provides: "GteError enum, crate::Result alias, ModelConfig struct with ExtractorMode, error.rs and model_config.rs modules"
provides:
  - "Tokenizer struct: loads tokenizer.json, configures TruncationParams + BatchLongest padding, encodes batch to Array2<i64>"
  - "Tokenized struct: input_ids, attn_masks, type_ids as Array2<i64>"
  - "build_session(): creates ORT Session from local ONNX file via Session::builder()?.commit_from_file()"
  - "run_session(): builds typed HashMap inputs, runs ORT session, extracts Array2<f32> by ExtractorMode"
  - "lib.rs updated with mod tokenizer and mod session declarations"
affects:
  - "02-rust-inference-core-03 (Embedder struct will consume Tokenizer + build_session + run_session)"
  - "02-rust-inference-core-04 (integration tests use Tokenizer and session functions)"

# Tech tracking
tech-stack:
  added:
    - "tokenizers = 0.21.0 (used: from_file, encode_batch, TruncationParams, PaddingParams::BatchLongest)"
    - "ort = 2.0.0-rc.9 with ndarray feature (used: Session::builder, commit_from_file, Value::from_array, try_extract_tensor)"
    - "ndarray = 0.16.0 (used: Array2::zeros, push_row, ArrayView, slice s![..], into_dimensionality::<Ix2>)"
    - "ort-sys = 2.0.0-rc.9 explicitly pinned to prevent rc.12 resolution"
  patterns:
    - "Tokenization: from_file → TruncationParams → BatchLongest → encode_batch → push_row into Array2<i64>"
    - "ORT session: Session::builder()?.commit_from_file() — v2 API, not v1 SessionBuilder::new()"
    - "Session inputs: HashMap<&str, Value<TensorValueType<i64>>> — all inputs are i64 typed"
    - "Embedding extraction: try_extract_tensor::<f32>() then match ExtractorMode for CLS slice or Raw dimensionality cast"
    - "Error propagation: crate::error::Result<T> imported in each module, with_truncation result always propagated with ?"

key-files:
  created:
    - ext/gte/src/tokenizer.rs
    - ext/gte/src/session.rs
  modified:
    - ext/gte/src/lib.rs
    - ext/gte/Cargo.toml
    - ext/gte/Cargo.lock

key-decisions:
  - "Use crate::error::Result<T> (imported) rather than crate::Result<T> (crate root) to avoid shadowing magnus::Error in lib.rs init function"
  - "Pin ort-sys = =2.0.0-rc.9 explicitly — ort 2.0.0-rc.9 depends on ort-sys with semver range, Cargo resolves to rc.12 which has breaking build script changes requiring TLS config"
  - "Tokenizer module does not expose position_ids — GTE v1 models (E5, CLIP, Siglip2) do not require it; deferred to future if needed"

patterns-established:
  - "Pattern: Rust modules import Result from crate::error, not from crate root"
  - "Pattern: ort-sys must be pinned alongside ort to prevent transitive version drift"

requirements-completed: [RUST-01, RUST-02, RUST-05]

# Metrics
duration: 4min
completed: 2026-04-07
---

# Phase 2 Plan 02: Tokenizer and ORT Session Modules Summary

**HuggingFace tokenizers batch-encoding to Array2<i64> tensors + ORT v2 Session build/run with typed HashMap inputs and CLS/Raw embedding extraction**

## Performance

- **Duration:** 4 min
- **Started:** 2026-04-07T02:43:14Z
- **Completed:** 2026-04-07T02:47:17Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments

- Tokenizer::new() loads tokenizer.json, configures TruncationParams at max_length, and BatchLongest padding — RUST-05 satisfied
- Tokenizer::tokenize() encodes a Vec<String> batch and builds three parallel Array2<i64> tensors (input_ids, attn_masks, type_ids)
- build_session() creates an ORT Session using v2 API Session::builder()?.commit_from_file() — RUST-02 satisfied
- run_session() builds typed HashMap inputs, runs session, and extracts Array2<f32> by ExtractorMode::Token(idx) or ExtractorMode::Raw — RUST-03 satisfied
- cargo check passes with zero errors inside nix develop

## Task Commits

Each task was committed atomically:

1. **Task 1: Create tokenizer.rs — batch tokenization to Array2 tensors** - `7a3476f` (feat)
2. **Task 2: Create session.rs — ORT session build, run, and embedding extraction** - `07c2316` (feat)

**Plan metadata:** (final docs commit, hash TBD)

## Files Created/Modified

- `/ext/gte/src/tokenizer.rs` - Tokenizer struct with new() and tokenize(); Tokenized output struct with input_ids/attn_masks/type_ids
- `/ext/gte/src/session.rs` - build_session() and run_session() public functions
- `/ext/gte/src/lib.rs` - Added `pub(crate) mod tokenizer;` and `pub(crate) mod session;` declarations
- `/ext/gte/Cargo.toml` - Added `ort-sys = "=2.0.0-rc.9"` explicit pin
- `/ext/gte/Cargo.lock` - Generated with resolved dependency tree including ort-sys rc.9 downgrade

## Decisions Made

- **crate::error::Result<T> imported locally, not re-exported at crate root:** The `init` function in lib.rs uses `magnus::Error` in its return type (`Result<(), Error>`). Re-exporting `crate::error::Result` at crate root would shadow this, causing a type mismatch. Each module imports `Result` from `crate::error` directly.
- **ort-sys pinned to =2.0.0-rc.9:** Without this, Cargo resolves ort-sys to v2.0.0-rc.12, which has a breaking build script requiring TLS configuration that conflicts with ORT_STRATEGY=system. Explicit pin restores correct build behavior.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Pinned ort-sys = =2.0.0-rc.9 to fix ort-sys rc.12 breaking build**
- **Found during:** Task 2 (cargo check verification)
- **Issue:** `ort 2.0.0-rc.9` specifies `ort-sys = "2.0.0-rc.9"` (semver range, not exact). Cargo resolved this to `ort-sys 2.0.0-rc.12`, which has a build script requiring TLS feature configuration (`tls-rustls`, `tls-native`, etc.) incompatible with `ORT_STRATEGY=system`.
- **Fix:** Added `ort-sys = "=2.0.0-rc.9"` as an explicit dependency in Cargo.toml to force the correct version
- **Files modified:** ext/gte/Cargo.toml, ext/gte/Cargo.lock
- **Verification:** cargo check output shows "Downgrading ort-sys v2.0.0-rc.12 -> v2.0.0-rc.9" and build succeeds
- **Committed in:** `07c2316` (Task 2 commit)

**2. [Rule 1 - Bug] Fixed crate::Result path — import from crate::error, not crate root**
- **Found during:** Task 2 (cargo check verification)
- **Issue:** Plan specified `crate::Result<T>` as the return type pattern. The `error.rs` module defines `pub type Result<T>` but lib.rs does not re-export it at crate root. Attempt to re-export caused `init` function's `Result<(), Error>` (using magnus::Error) to be shadowed, producing type mismatch errors.
- **Fix:** Changed all `crate::Result<T>` to use `use crate::error::Result;` import in each module
- **Files modified:** ext/gte/src/tokenizer.rs, ext/gte/src/session.rs
- **Verification:** cargo check passes with zero errors
- **Committed in:** `07c2316` (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (1 blocking — ort-sys version drift; 1 bug — Result path resolution)
**Impact on plan:** Both fixes necessary for cargo check to pass. No scope creep. The ort-sys pin is a forward-looking correctness fix ensuring reproducible builds.

## Issues Encountered

- ort-sys transitive dependency version drift is a known risk with pinned RC crates — the explicit ort-sys pin should be documented for Plan 03 onwards as a convention.

## User Setup Required

None — no external service configuration required. Model files remain user-provided (out of scope for Phase 2 per D-05).

## Next Phase Readiness

- tokenizer.rs and session.rs are complete and compile cleanly
- Plan 03 (Embedder) can immediately use `Tokenizer::new()`, `Tokenizer::tokenize()`, `build_session()`, and `run_session()`
- All three inference building blocks (RUST-01 tokenize, RUST-02 session run, RUST-03 extraction) are implemented
- Integration tests (RUST-04) with fixture model files remain for Plan 04

---
*Phase: 02-rust-inference-core*
*Completed: 2026-04-07*

## Self-Check: PASSED

- FOUND: ext/gte/src/tokenizer.rs
- FOUND: ext/gte/src/session.rs
- FOUND: .planning/phases/02-rust-inference-core/02-02-SUMMARY.md
- FOUND commit: 7a3476f (feat: tokenizer.rs)
- FOUND commit: 07c2316 (feat: session.rs + lib.rs + Cargo fixes)
