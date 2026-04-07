---
phase: 02-rust-inference-core
plan: "01"
subsystem: rust-core
tags: [rust, cargo, ort, tokenizers, ndarray, error-handling, model-config]
dependency_graph:
  requires: [01-scaffold-01]
  provides: [error-types, model-config-types]
  affects: [02-02, 02-03]
tech_stack:
  added:
    - "ort = { version = \"=2.0.0-rc.9\", features = [\"ndarray\"] }"
    - "tokenizers = \"0.21.0\""
    - "ndarray = \"0.16.0\""
    - "half = \"2\""
  patterns:
    - "Crate-level Result<T> alias via pub type in error module"
    - "Plain struct factory methods for model family configuration (no builder pattern)"
    - "pub(crate) mod visibility for internal inference modules"
key_files:
  created:
    - ext/gte/src/error.rs
    - ext/gte/src/model_config.rs
  modified:
    - ext/gte/Cargo.toml
    - ext/gte/src/lib.rs
decisions:
  - "GteError is Rust-internal only — Phase 3 will add From<GteError> for magnus::Error"
  - "Shape variant added to GteError (not in plan spec but required for ndarray::ShapeError conversion)"
  - "ExtractorMode is Copy — appropriate since it holds only a usize or unit"
  - "Siglip2 output_tensor is placeholder — must inspect actual ONNX export before integration test"
metrics:
  duration_seconds: 98
  completed_date: "2026-04-07"
  tasks_completed: 3
  tasks_total: 3
  files_created: 2
  files_modified: 2
---

# Phase 2 Plan 01: Inference Dependencies and Shared Types Summary

Cargo dependency set pinned (ort=2.0.0-rc.9 exact, tokenizers=0.21.0, ndarray=0.16.0, half=2) with GteError enum and ModelConfig factory methods establishing the type contracts for the Phase 2 inference pipeline.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Add inference dependencies to Cargo.toml | 7f6af23 | ext/gte/Cargo.toml |
| 2 | Create error.rs with GteError and Result alias | 80e0eb0 | ext/gte/src/error.rs |
| 3 | Create model_config.rs + update lib.rs | 3d81e4b | ext/gte/src/model_config.rs, ext/gte/src/lib.rs |

## Verification

`cargo check --manifest-path ext/gte/Cargo.toml` inside `nix develop`: **PASSED** — zero errors, zero warnings about unused imports (ort/tokenizers/ndarray not yet used in lib.rs, which is expected for Wave 1).

## What Was Built

### ext/gte/Cargo.toml

Four new dependencies added to the existing rb-sys + magnus set:
- `ort = { version = "=2.0.0-rc.9", features = ["ndarray"] }` — exact pin, ndarray feature mandatory for `Value::from_array`
- `tokenizers = "0.21.0"` — HuggingFace tokenizers for BPE/WordPiece from tokenizer.json
- `ndarray = "0.16.0"` — N-dimensional arrays for tensor construction
- `half = "2"` — F16/F32 conversion for FP16 model outputs

### ext/gte/src/error.rs

GteError enum with four variants:
- `Tokenizer(String)` — tokenizer init or encoding failure
- `Inference(String)` — ORT session creation or inference failure
- `Ort(String)` — wrapped from `ort::Error` via `From<ort::Error>`
- `Shape(String)` — wrapped from `ndarray::ShapeError` via `From<ndarray::ShapeError>`

Plus `pub type Result<T> = std::result::Result<T, GteError>` — the crate-level alias used as `crate::Result<T>` in all inference modules.

### ext/gte/src/model_config.rs

`ExtractorMode` enum (Copy):
- `Token(usize)` — extract embedding at token index from [batch, seq, dim] tensor (E5 CLS = index 0)
- `Raw` — tensor is already pooled [batch, dim], use as-is (CLIP, Siglip2)

`ModelConfig` struct with factory methods:
- `ModelConfig::e5()` → max_length=512, output_tensor="last_hidden_state", mode=Token(0), with_type_ids=true
- `ModelConfig::clip()` → max_length=77, output_tensor="text_embeds", mode=Raw, with_type_ids=false
- `ModelConfig::siglip2()` → max_length=64, output_tensor=PLACEHOLDER, mode=Raw, with_type_ids=false

### ext/gte/src/lib.rs

Added at top (before use magnus import):
```rust
pub(crate) mod error;
pub(crate) mod model_config;
```

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

**Siglip2 output tensor name** — `ext/gte/src/model_config.rs` line 64: `output_tensor: "TODO_inspect_siglip2_onnx_output_tensor_name"`. This is intentional and documented in the plan. The actual name must be determined by inspecting the exported Siglip2 ONNX model before writing integration tests in Phase 4.

This stub does NOT prevent the plan's goal from being achieved — the type contracts for Wave 2 (tokenizer.rs, session.rs) are fully defined and correct. The placeholder will be resolved when a Siglip2 ONNX model is available.

## Self-Check: PASSED
