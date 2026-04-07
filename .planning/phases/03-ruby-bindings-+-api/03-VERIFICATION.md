---
phase: 03-ruby-bindings-+-api
verified: 2026-04-07T12:00:00Z
status: passed
score: 6/6 must-haves verified
---

# Phase 3: Ruby Bindings + API Verification Report

**Phase Goal:** Developer can call `GTE::E5.new(model_path:).embed_query(text)` from Ruby, receive an L2-normalized `Array<Float>`, with GVL released during inference and all Rust errors surfaced as `GTE::Error`
**Verified:** 2026-04-07
**Status:** passed
**Re-verification:** No -- initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `GTE::Embedder.new(tokenizer_path, model_path, config)` returns a Ruby object and `embedder.embed(["text"])` returns `Array<Array<Float>>` | VERIFIED | `ext/gte/src/ruby_embedder.rs` lines 34-53: `rb_new` creates `RbEmbedder`; lines 55-80: `rb_embed` returns `RArray` via `array2_to_rarray`; `register()` wires `.new` and `#embed`; RSpec structural tests pass (29 examples, 0 failures) |
| 2 | Concurrent Ruby threads calling `embedder.embed` simultaneously do not block each other (GVL released during `session.run`) | VERIFIED | `ext/gte/src/ruby_embedder.rs` lines 27-31: `run_without_gvl` extern C fn; lines 68-74: `rb_sys::rb_thread_call_without_gvl` wraps only `run_without_gvl`; tokenization stays inside GVL (line 59) |
| 3 | `GTE::E5.new(model_path:).embed_query("find docs")` prepends `"query: "` and `embed_passage("content")` prepends `"passage: "` | VERIFIED | `lib/gte/e5.rb` line 23: `"query: #{text}"`; line 29: `"passage: #{text}"`; both call `@embedder.embed([...]).first` returning single vector |
| 4 | `GTE::CLIP.new(model_path:)` and `GTE::Siglip2.new(model_path:)` instantiate with correct per-family defaults | VERIFIED | `lib/gte/clip.rb` passes `"clip"` to `GTE::Embedder.new`; `lib/gte/siglip2.rb` passes `"siglip2"`; `ruby_embedder.rs` maps these to `ModelConfig::clip()` and `ModelConfig::siglip2()` |
| 5 | `GTE.configure { |c| c.model_path = "..." }` sets global defaults and `GTE.default` returns a memoized embedder | VERIFIED | `lib/gte/configuration.rb`: `configure` yields config, `default` memoizes via `@default ||=`, `reset_default!` clears it; `configuration_spec.rb` tests all paths including memoization and reset |
| 6 | Embedding output vectors are L2-normalized by default | VERIFIED | `ext/gte/src/embedder.rs` lines 79-87: `normalize_l2` with zero-vector guard; `ruby_embedder.rs` line 78: called before `array2_to_rarray`; `embedder_spec.rb` has L2 norm, dot product, and Rust-vs-Ruby normalization tests |

**Score:** 6/6 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `ext/gte/src/ruby_embedder.rs` | RbEmbedder #[wrap] with GVL release | VERIFIED | 101 lines; `#[wrap(class = "GTE::Embedder")]`, `rb_thread_call_without_gvl`, `normalize_l2` call, `array2_to_rarray` conversion |
| `ext/gte/src/embedder.rs` | normalize_l2 + split tokenize/run | VERIFIED | 87 lines; `pub fn normalize_l2`, `pub fn tokenize`, `pub fn run`, zero-vector guard |
| `ext/gte/src/error.rs` | From<GteError> for magnus::Error | VERIFIED | Lines 43-58; `#[cfg(feature = "ruby-ffi")]` gated; uses `module.const_get::<_, magnus::ExceptionClass>("Error")` |
| `ext/gte/src/lib.rs` | init() registers GTE::Embedder | VERIFIED | Line 28: `crate::ruby_embedder::register(ruby)?;`; Line 12: `mod ruby_embedder;` |
| `lib/gte/e5.rb` | E5 class with embed/embed_query/embed_passage | VERIFIED | 32 lines; `class E5`, `"query: #{text}"`, `"passage: #{text}"` |
| `lib/gte/clip.rb` | CLIP class with embed | VERIFIED | 18 lines; `class CLIP`, passes `"clip"` config |
| `lib/gte/siglip2.rb` | Siglip2 class with embed | VERIFIED | 19 lines; `class Siglip2`, passes `"siglip2"` config |
| `lib/gte/configuration.rb` | Configuration + configure/default/reset_default! | VERIFIED | 44 lines; `class Configuration`, `def configure`, `def default`, `def reset_default!` |
| `lib/gte.rb` | Requires all new files | VERIFIED | Has `require_relative` for configuration, e5, clip, siglip2 |
| `spec/gte/embedder_spec.rb` | Structural + correctness tests | VERIFIED | 181 lines; L2 norm, NaN, Inf, dot product, prefix difference tests |
| `spec/gte/e5_spec.rb` | E5 structural + behavioral specs | VERIFIED | 89 lines; embed_query/embed_passage prefix and norm tests |
| `spec/gte/clip_spec.rb` | CLIP structural specs | VERIFIED | 47 lines; class structure + fixture-gated embed test |
| `spec/gte/siglip2_spec.rb` | Siglip2 structural specs | VERIFIED | 35 lines; class structure + pending fixture test |
| `spec/gte/configuration_spec.rb` | Configuration lifecycle specs | VERIFIED | 115 lines; configure, config, default, reset_default! with after-block cleanup |
| `spec/support/fixtures.rb` | Fixture guard helper | VERIFIED | 19 lines; GTE_FIXTURES_AVAILABLE, GTE_MODEL_PATH, GTE_TOKENIZER_PATH |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `ruby_embedder.rs rb_embed` | `embedder.rs tokenize + run` | Split tokenize/run for GVL release | WIRED | Line 59: `rb_self.inner.tokenize(&texts)`, line 30: `(*args.embedder).run(&*args.tokenized)` |
| `ruby_embedder.rs rb_embed` | `rb_sys::rb_thread_call_without_gvl` | Unsafe extern C fn wrapping session run | WIRED | Line 68: `rb_sys::rb_thread_call_without_gvl(Some(run_without_gvl), ...)` |
| `error.rs` | `magnus::Error` | Feature-gated From impl | WIRED | Line 44: `impl From<GteError> for magnus::Error` with `#[cfg(feature = "ruby-ffi")]` |
| `lib/gte/e5.rb initialize` | `GTE::Embedder.new` | Calls with config "e5" | WIRED | Line 12: `GTE::Embedder.new(resolved_tokenizer, model_path, "e5")` |
| `lib/gte/e5.rb embed_query` | `GTE::Embedder#embed` | Prepends "query: " prefix | WIRED | Line 23: `@embedder.embed(["query: #{text}"]).first` |
| `lib/gte/configuration.rb default` | `GTE::E5/CLIP/Siglip2` | `const_get` dispatch | WIRED | Line 31: `const_get(config.model_family.to_s.upcase)` |
| `lib/gte.rb` | All new modules | require_relative | WIRED | Lines 5-8: requires configuration, e5, clip, siglip2 |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| RSpec suite passes | `bundle exec rspec` | 29 examples, 0 failures, 5 pending | PASS (user-confirmed) |
| Native extension compiles and loads | `bundle exec rake compile` | Produces .bundle | PASS (user-confirmed) |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| BIND-01 | 03-01 | `GTE::Embedder.new` creates Ruby object wrapping Rust struct | SATISFIED | `ruby_embedder.rs` `#[wrap]` + `rb_new` + `register()` |
| BIND-02 | 03-01 | `embedder.embed(texts)` returns `Array<Array<Float>>` | SATISFIED | `rb_embed` + `array2_to_rarray` conversion |
| BIND-03 | 03-01 | GVL released during inference | SATISFIED | `rb_thread_call_without_gvl` wrapping `run_without_gvl` |
| BIND-04 | 03-01 | Rust errors converted to `GTE::Error` | SATISFIED | `From<GteError> for magnus::Error` impl; spec tests `raise_error(GTE::Error)` |
| API-01 | 03-02 | `GTE::E5.new(model_path:)` with E5 defaults | SATISFIED | `lib/gte/e5.rb` passes `"e5"` config |
| API-02 | 03-02 | `GTE::CLIP.new(model_path:)` with CLIP defaults | SATISFIED | `lib/gte/clip.rb` passes `"clip"` config |
| API-03 | 03-02 | `GTE::Siglip2.new(model_path:)` with Siglip2 defaults | SATISFIED | `lib/gte/siglip2.rb` passes `"siglip2"` config |
| API-04 | 03-02 | `embed_query` prepends "query: " | SATISFIED | `lib/gte/e5.rb` line 23 |
| API-05 | 03-02 | `embed_passage` prepends "passage: " | SATISFIED | `lib/gte/e5.rb` line 29 |
| API-06 | 03-02 | `GTE.configure` + `GTE.default` | SATISFIED | `lib/gte/configuration.rb` + `configuration_spec.rb` |
| API-07 | 03-01 | L2-normalized output by default | SATISFIED | `embedder.rs normalize_l2` called in `ruby_embedder.rs rb_embed` |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `spec/gte/siglip2_spec.rb` | 24 | `pending "Requires inspecting actual Siglip2 ONNX"` | Info | Known limitation -- Siglip2 output tensor name is LOW CONFIDENCE; test correctly marked pending |

### Human Verification Required

### 1. GVL Release Under Concurrency

**Test:** Run two Ruby threads calling `embedder.embed` simultaneously with a real model; verify neither thread blocks the other using timing assertions.
**Expected:** Both threads complete in roughly the same wall-clock time as one (parallelism, not serialized).
**Why human:** Requires a running ONNX model fixture and thread timing measurement.

### 2. End-to-End Embedding Correctness

**Test:** With a real E5 model, run `GTE::E5.new(model_path:).embed_query("test")` and verify the output vector has the expected dimension and L2 norm of 1.0.
**Expected:** Returns a 768-element Float array with L2 norm within 0.001 of 1.0.
**Why human:** Requires real ONNX model files (fixture-gated tests cover this when GTE_MODEL_PATH is set).

### Gaps Summary

No gaps found. All 11 requirements (BIND-01 through BIND-04, API-01 through API-07) are satisfied. All artifacts exist, are substantive (no stubs), and are properly wired. The RSpec suite passes with 29 examples, 0 failures, and 5 pending fixture-gated tests. The only notable item is the Siglip2 output tensor name being LOW CONFIDENCE, which is correctly documented and test-gated.

---

_Verified: 2026-04-07_
_Verifier: Claude (gsd-verifier)_
