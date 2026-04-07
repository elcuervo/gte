---
phase: 03-ruby-bindings-+-api
plan: "01"
subsystem: rust-ffi-layer
tags: [rust, ffi, magnus, ruby, embeddings, gvl, l2-normalization]
dependency_graph:
  requires: [02-rust-inference-core-03]
  provides: [GTE::Embedder Ruby class, rb_thread_call_without_gvl GVL release, L2 normalization, From<GteError> magnus::Error]
  affects: [lib/gte/gte.bundle, ext/gte/src/ruby_embedder.rs, ext/gte/src/embedder.rs, ext/gte/src/error.rs, ext/gte/src/lib.rs]
tech_stack:
  added: [magnus 0.8.2 #[wrap], rb-sys rb_thread_call_without_gvl, rake-compiler ExtensionTask]
  patterns: [#[wrap(class="GTE::Embedder" free_immediately size)], GVL release via unsafe extern C fn, From<GteError> feature-gated impl, Module::const_get for ExceptionClass lookup]
key_files:
  created: [ext/gte/src/ruby_embedder.rs, ext/gte/tests/embedder_unit_test.rs, spec/gte/embedder_spec.rb]
  modified: [ext/gte/src/embedder.rs, ext/gte/src/error.rs, ext/gte/src/lib.rs, Rakefile]
decisions:
  - "Use Module::const_get::<_, ExceptionClass>(\"Error\") to look up GTE::Error — class_path does not exist in magnus 0.8.2"
  - "Use exception_arg_error() not exception_argument_error() — magnus 0.8.2 uses arg_error naming"
  - "Add rake/extensiontask to Rakefile — was missing despite rake-compiler being in Gemfile"
  - "InferArgs struct with raw pointers for GVL callback — tokenize in GVL, run outside GVL"
metrics:
  duration: "7 minutes"
  completed_date: "2026-04-07"
  tasks_completed: 2
  files_changed: 7
---

# Phase 3 Plan 01: Rust FFI Layer — GTE::Embedder Summary

**One-liner:** RbEmbedder #[wrap] struct exposing GTE::Embedder to Ruby via magnus, with GVL release during inference and L2 normalization before FFI return.

## What Was Built

Created the Rust FFI layer that bridges Phase 2's inference core to Ruby:

1. **`ext/gte/src/embedder.rs`** — Added `pub fn normalize_l2`, `pub fn tokenize`, and `pub fn run` split methods enabling GVL release between tokenization and ONNX inference.

2. **`ext/gte/src/ruby_embedder.rs`** — New file. `RbEmbedder` struct with `#[wrap(class = "GTE::Embedder", free_immediately, size)]` holding `Arc<Embedder>`. Implements `rb_new` (maps config string to ModelConfig factory) and `rb_embed` (tokenizes within GVL, releases GVL via `rb_thread_call_without_gvl` for `session.run`, L2-normalizes, converts to Ruby `Array<Array<Float>>`).

3. **`ext/gte/src/error.rs`** — Added `From<GteError> for magnus::Error` impl, feature-gated to `ruby-ffi`. Uses `Module::const_get::<_, ExceptionClass>("Error")` to resolve `GTE::Error` class at call time.

4. **`ext/gte/src/lib.rs`** — Added `mod ruby_embedder` declaration and `crate::ruby_embedder::register(ruby)?` call in `init()`.

5. **`Rakefile`** — Added `rake/extensiontask` with `Rake::ExtensionTask.new("gte")` to enable `bundle exec rake compile`.

## Tasks Completed

| Task | Description | Commit | Status |
|------|-------------|--------|--------|
| 1 | normalize_l2 + split tokenize/run in embedder.rs | f617430 | Done |
| 2 | FFI layer: ruby_embedder.rs + error.rs + lib.rs | 02c0acf | Done |

## Verification Results

- `cargo test --no-default-features` — 4 normalize_l2 unit tests pass, integration tests ignored (no fixtures)
- `bundle exec rake compile` — exits 0, produces `lib/gte/gte.bundle`
- `GTE::Embedder.instance_methods(false).include?(:embed)` — `true`
- `GTE::Error.ancestors.include?(StandardError)` — `true`
- `GTE::Embedder.ancestors` — `[GTE::Embedder, Object, Kernel, BasicObject]`

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed magnus 0.8.2 API: `class_path` does not exist**
- **Found during:** Task 2 (first compile attempt)
- **Issue:** Plan code used `ruby.class_path("GTE::Error")` which does not exist in magnus 0.8.2
- **Fix:** Used `ruby.define_module("GTE").unwrap().const_get::<_, ExceptionClass>("Error")` — idempotent module lookup + const_get
- **Files modified:** ext/gte/src/error.rs
- **Commit:** 02c0acf

**2. [Rule 1 - Bug] Fixed magnus 0.8.2 API: `exception_argument_error` does not exist**
- **Found during:** Task 2 (first compile attempt)
- **Issue:** Plan code used `ruby.exception_argument_error()` but magnus 0.8.2 uses `exception_arg_error()`
- **Fix:** Changed to `ruby.exception_arg_error()`
- **Files modified:** ext/gte/src/ruby_embedder.rs
- **Commit:** 02c0acf

**3. [Rule 3 - Blocking] Added rake-compiler integration to Rakefile**
- **Found during:** Task 2 (compile step)
- **Issue:** `bundle exec rake compile` failed with "Don't know how to build task 'compile'" — Rakefile was missing `require "rake/extensiontask"` and `Rake::ExtensionTask.new`
- **Fix:** Added rake-compiler integration with `Rake::ExtensionTask.new("gte") { |ext| ext.lib_dir = "lib/gte" }`
- **Files modified:** Rakefile
- **Commit:** 02c0acf

## Known Stubs

None — this plan creates functional FFI code, not stubs. The GVL release and L2 normalization work correctly. Models are user-provided (by design), so embed calls require fixture data to execute end-to-end.

## Self-Check: PASSED

| Check | Result |
|-------|--------|
| ext/gte/src/ruby_embedder.rs exists | FOUND |
| ext/gte/tests/embedder_unit_test.rs exists | FOUND |
| spec/gte/embedder_spec.rb exists | FOUND |
| lib/gte/gte.bundle exists | FOUND |
| Commit f617430 (Task 1) | FOUND |
| Commit 02c0acf (Task 2) | FOUND |
