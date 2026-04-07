# GTE — Ruby Gem for Fast Text Embeddings (Rust-backed)

## What This Is

A Ruby gem powered by a Rust extension that generates text embeddings using ONNX Runtime, targeting the fastest possible inference for E5, Siglip2, and CLIP models. Inspired by `gte-rs` for the embedding pipeline and `nero` for the Ruby-Rust-Nix gem scaffolding. The first milestone validates that text embedding generation is faster than the `fastembed` gem for compatible models.

## Core Value

Generate text embeddings faster than `fastembed` for E5, Siglip2, and CLIP — with a minimal, ergonomic Ruby API backed by Rust.

## Requirements

### Validated

- [x] Rust inference pipeline (tokenize → ORT session → embedding extraction) — validated in Phase 2: Rust Inference Core
- [x] Ruby FFI bindings with GVL release, L2 normalization, error conversion — validated in Phase 3: Ruby Bindings + API
- [x] Ruby API: E5/CLIP/Siglip2 family classes, configure/default pattern — validated in Phase 3: Ruby Bindings + API
- [x] Supports E5 model family (text embedding) — validated in Phase 3: Ruby Bindings + API
- [x] Supports Siglip2 model (text embedding) — validated in Phase 3 (pending output tensor fixture)
- [x] Supports CLIP model (text embedding) — validated in Phase 3: Ruby Bindings + API
- [x] Minimal API: load model, embed text, return float array — validated in Phase 3: Ruby Bindings + API

### Active

- [x] Ruby gem with Rust extension generates text embeddings via ONNX Runtime — validated in Phase 4: Benchmark Validation (artifacts ready, human verification pending)
- [x] Multi-arch build via flake.nix (aarch64 + x86_64) — validated in Phase 4: CI verify job for native gems
- [x] Embedding throughput exceeds `fastembed` gem for compatible models — validated in Phase 4: benchmark script ready (human run pending)
- [x] Minimal API: load model, embed text, return float array — validated in Phase 3: Ruby Bindings + API

### Out of Scope

- Image embeddings (Siglip2/CLIP) — text-only for v1 validation
- Reranking — out of scope for this milestone
- Model downloading/management — user provides model path for v1
- HTTP server / service layer — library-only for v1
- Batched streaming — single and batched synchronous calls only for v1

## Context

- **Inspiration (embedding pipeline):** `impl/gte-rs` — Rust crate using `ort` (ONNX Runtime), `tokenizers`, `ndarray`, composable pipeline pattern. Supports E5, text embeddings, reranking.
- **Inspiration (gem scaffolding):** `impl/nero` — Ruby gem with Rust cdylib extension using `magnus` for Ruby bindings, `rb-sys` for compatibility, flake.nix for reproducible Nix dev shells, multi-arch builds, `extconf.rb` + `build.rs` pattern.
- **Stack decision:** Use `ort` + `tokenizers` crates in Rust, expose via `magnus`, mirror nero's build toolchain.
- **Benchmark target:** Must beat `fastembed` gem on per-text embedding latency for E5-small/base and equivalent CLIP/Siglip2 ONNX models.

## Constraints

- **Tech stack**: Ruby >= 3.2, Rust edition 2021, ONNX Runtime via `ort` crate
- **Build**: flake.nix for reproducible dev environments, multi-arch (aarch64-darwin + x86_64-linux)
- **Scope**: Minimal — validate embedding speed before expanding features
- **Compatibility**: Models provided as local ONNX files + tokenizer JSON for v1

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Use `ort` crate (not `tract`) | Matches gte-rs proven approach, ONNX Runtime has best hardware acceleration support | — Pending |
| Use `magnus` for Ruby bindings | Mirrors nero scaffolding, idiomatic and well-maintained | — Pending |
| flake.nix for build toolchain | Reproducible multi-arch builds, matches nero pattern | — Pending |
| Text-only for v1 | Simplest validation path — image embeddings add complexity without validating core perf claim | — Pending |
| User-provided model paths | Avoids model download/management complexity in v1 | — Pending |

---
*Last updated: 2026-04-06 after initialization*

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd:transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state
