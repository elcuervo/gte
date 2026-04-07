# Roadmap: GTE

## Overview

GTE is a Ruby gem backed by a Rust cdylib extension that generates text embeddings via ONNX Runtime, targeting E5, Siglip2, and CLIP model families. The milestone validates that embedding throughput exceeds the `fastembed` gem. Phases proceed in strict dependency order: the build toolchain must exist before any Rust code runs, Rust inference must be validated before FFI is added, and the full Ruby API must be correct before benchmarks are meaningful.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Scaffold** - Nix dev shell + build toolchain + extension loads + error handling
- [x] **Phase 2: Rust Inference Core** - Full tokenize → ONNX → extract pipeline validated with real models (completed 2026-04-07)
- [ ] **Phase 3: Ruby Bindings + API** - magnus `#[wrap]`, GVL release, model presets, E5 prefixes, configure block
- [ ] **Phase 4: Benchmark Validation** - Prove faster than fastembed at batch sizes 1/8/32, multi-arch packaging

## Phase Details

### Phase 1: Scaffold
**Goal**: Developer can enter a reproducible Nix dev environment, compile the extension, load the gem, and have panic-safe error handling in place before any inference code exists
**Depends on**: Nothing (first phase)
**Requirements**: SCAF-01, SCAF-02, SCAF-03, SCAF-04, SCAF-05, SCAF-06
**Success Criteria** (what must be TRUE):
  1. Developer runs `nix develop` and gets a shell with Ruby 3.4, Rust, ONNX Runtime, and all build dependencies on PATH
  2. `bundle exec rake compile` succeeds and produces a native `.so`/`.bundle` file
  3. `require 'gte'` in Ruby loads without error
  4. `GTE::Error` exception class exists and Rust panics surface as `GTE::Error` rather than crashing the Ruby process
  5. GitHub Actions CI produces native gems for `aarch64-apple-darwin` and `x86_64-unknown-linux-gnu`
**Plans**: 2 plans

Plans:
- [x] 01-01-PLAN.md — Gem scaffold + Rust extension skeleton + Nix devShell (SCAF-01 through SCAF-05)
- [x] 01-02-PLAN.md — GitHub Actions CI cross-compilation workflow (SCAF-06)

### Phase 2: Rust Inference Core
**Goal**: The full tokenize → ONNX session → embedding extraction pipeline runs correctly in Rust integration tests against real model files, before any Ruby FFI is added
**Depends on**: Phase 1
**Requirements**: RUST-01, RUST-02, RUST-03, RUST-04, RUST-05
**Success Criteria** (what must be TRUE):
  1. A Rust integration test tokenizes a batch of strings using a local `tokenizer.json` and produces correct `input_ids` and `attention_mask` tensors
  2. A Rust integration test runs an E5 ONNX session and returns embeddings that match Python sentence-transformers reference output within float32 tolerance
  3. A Rust integration test confirms that inputs exceeding model max token length (512 E5 / 77 CLIP / 64 Siglip2) are truncated without error
  4. All three model families (E5, CLIP, Siglip2) have a `ModelConfig` that drives correct output extraction via `ExtractorMode`
**Plans**: 3 plans

Plans:
- [x] 02-01-PLAN.md — Cargo deps + error.rs + model_config.rs (RUST-03, RUST-05 — contracts)
- [x] 02-02-PLAN.md — tokenizer.rs + session.rs (RUST-01, RUST-02, RUST-05 — implementations)
- [x] 02-03-PLAN.md — embedder.rs + test scaffolding (RUST-03, RUST-04 — integration + tests)

### Phase 3: Ruby Bindings + API
**Goal**: Developer can call `GTE::E5.new(model_path:).embed_query(text)` from Ruby, receive an L2-normalized `Array<Float>`, with GVL released during inference and all Rust errors surfaced as `GTE::Error`
**Depends on**: Phase 2
**Requirements**: BIND-01, BIND-02, BIND-03, BIND-04, API-01, API-02, API-03, API-04, API-05, API-06, API-07
**Success Criteria** (what must be TRUE):
  1. `GTE::Embedder.new(tokenizer_path:, model_path:, config:)` returns a Ruby object and `embedder.embed(["text"])` returns `Array<Array<Float>>`
  2. Concurrent Ruby threads calling `embedder.embed` simultaneously do not block each other (GVL released during `session.run`)
  3. `GTE::E5.new(model_path:).embed_query("find docs")` prepends `"query: "` and `embed_passage("content")` prepends `"passage: "` before embedding
  4. `GTE::CLIP.new(model_path:)` and `GTE::Siglip2.new(model_path:)` instantiate with correct per-family defaults without requiring explicit config
  5. `GTE.configure { |c| c.model_path = "..." }` sets global defaults and `GTE.default` returns a memoized embedder instance
  6. Embedding output vectors are L2-normalized by default (dot product of two embeddings equals cosine similarity)
**Plans**: 3 plans

Plans:
- [x] 03-01-PLAN.md — Rust FFI layer: RbEmbedder #[wrap], GVL release, L2 normalization, error conversion (BIND-01, BIND-02, BIND-03, BIND-04, API-07)
- [x] 03-02-PLAN.md — Pure Ruby API layer: E5/CLIP/Siglip2 family classes, configuration, embedder_spec with correctness tests (API-01, API-02, API-03, API-04, API-05, API-06)
- [x] 03-03-PLAN.md — RSpec suite for Ruby API layer: e5_spec, clip_spec, siglip2_spec, configuration_spec (API-01, API-02, API-03, API-04, API-05, API-06)

### Phase 4: Benchmark Validation
**Goal**: GTE embedding throughput is demonstrably faster than the `fastembed` gem at batch sizes 1, 8, and 32, validated with correct warm-up methodology, and the gem packages as a native binary for all target architectures
**Depends on**: Phase 3
**Requirements**: BENCH-01, BENCH-02
**Success Criteria** (what must be TRUE):
  1. A benchmark suite runs at least 3 warm-up iterations before timing and reports GTE throughput exceeding `fastembed` for E5-small on batch size 1
  2. Benchmark results cover batch sizes 1, 8, and 32 texts and GTE leads `fastembed` across all three
  3. Binary gems for `aarch64-apple-darwin` and `x86_64-unknown-linux-gnu` install and run `embed` successfully without requiring a local Rust toolchain
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Scaffold | 1/2 | In Progress|  |
| 2. Rust Inference Core | 2/3 | Complete    | 2026-04-07 |
| 3. Ruby Bindings + API | 2/3 | In Progress|  |
| 4. Benchmark Validation | 0/? | Not started | - |
