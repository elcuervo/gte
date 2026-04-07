# Phase 3: Ruby Bindings + API - Research

**Researched:** 2026-04-07
**Domain:** magnus FFI bindings, rb-sys raw C API, Ruby module/class design, GVL release
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** GVL is released **only during `session.run`** — the ORT inference call is the bottleneck; tokenization stays within the GVL (fast and tokenizer internals may not be `Send`)
- **D-02:** GVL release uses `ruby.thread_call_without_gvl(|| ...)` — the magnus-provided safe wrapper for `rb_thread_call_without_gvl`; no manual unsafe FFI
- **D-03:** `Session` is wrapped in `Arc` so multiple Ruby threads can share the same `Embedder` concurrently without blocking. The `#[wrap]` struct uses `free_immediately` (magnus pattern from nero reference)
- **D-04:** Error conversion at FFI boundary: `GteError` → `GTE::Error` (already defined in Phase 1) via `Error::new(gte_error_class, msg)` in every Rust FFI method; never leak Rust error strings as RuntimeError
- **D-05:** E5, CLIP, and Siglip2 family classes are **pure Ruby** in `lib/gte/e5.rb`, `lib/gte/clip.rb`, `lib/gte/siglip2.rb` — each wraps a `GTE::Embedder` instance with family-specific defaults (model config, tokenizer defaults). No additional Rust structs per family.
- **D-06:** `embed_query(text)` and `embed_passage(text)` are Ruby methods on `GTE::E5` that prepend `"query: "` / `"passage: "` to the input string before calling `@embedder.embed([prefixed_text])`. E5 semantics stay in the Ruby layer.
- **D-07:** `GTE.configure { |c| c.model_path = "..." }` is a pure Ruby module-level pattern: a `Configuration` struct (Ruby class), `@@config` module variable, and `GTE.default` that memoizes an embedder from the current config. No Rust singleton.
- **D-08:** L2 normalization happens **in Rust** before the FFI return — normalize each row of `Array2<f32>` to unit length, then convert to `Array<Array<Float>>`. This ensures dot product == cosine similarity without Ruby overhead.

### Claude's Discretion

- Exact magnus `#[wrap]` attribute options (class name, mark vs free_immediately choice)
- Whether to expose `GTE::Embedder` directly as a public Ruby class or keep it as implementation detail
- How many threads to pre-approve in `thread_call_without_gvl` (unblocking Ruby's thread scheduler)
- Exact `Configuration` Ruby class API surface (which fields, any validation)
- RSpec test structure (shared examples vs separate spec files per class)

### Deferred Ideas (OUT OF SCOPE)

- Image embeddings (CLIP/Siglip2 vision) — out of scope for v1, text-only
- Model downloading/management — user provides model path
- Streaming/async embed — synchronous only for v1
- RubyGems.org publish — Phase 4 concern
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| BIND-01 | `GTE::Embedder.new(tokenizer_path:, model_path:, config:)` creates a Ruby object wrapping the Rust `#[wrap]` struct | `#[wrap(class = "GTE::Embedder", free_immediately, size)]` on a struct holding `Arc<Embedder>`; `define_singleton_method("new", function!(RbEmbedder::new, 3))` |
| BIND-02 | `embedder.embed(texts)` accepts Ruby `Array<String>` and returns `Array<Array<Float>>` | `method!(RbEmbedder::embed, 1)` with `RArray` → `Vec<String>` conversion; L2-normalize each row before converting ndarray → nested RArray |
| BIND-03 | GVL released during Rust inference call so concurrent Ruby threads are not blocked | `rb_thread_call_without_gvl` via rb-sys raw binding — wraps only `session.run()`; Session is `Send + Sync` in ort 2.0.0-rc.9 |
| BIND-04 | All Rust errors converted to `GTE::Error` Ruby exceptions — no segfaults or unhandled panics | `From<GteError> for magnus::Error` impl: `Error::new(ruby.class_path("GTE::Error"), msg.to_string())`; panic hook already installed in Phase 1 |
| API-01 | `GTE::E5.new(model_path:)` uses correct E5 defaults | Pure Ruby: `ModelConfig::e5()` defaults already in Rust; Ruby class calls `GTE::Embedder.new` with those config symbol args |
| API-02 | `GTE::CLIP.new(model_path:)` uses correct CLIP defaults | Pure Ruby class wrapping `GTE::Embedder.new` with clip config args |
| API-03 | `GTE::Siglip2.new(model_path:)` uses Siglip2 defaults | LOW CONFIDENCE on `output_tensor` name — must inspect model before setting default; tracked as blocker from Phase 2 |
| API-04 | `GTE::E5#embed_query(text)` prepends `"query: "` | Pure Ruby: `@embedder.embed(["query: #{text}"])[0]` |
| API-05 | `GTE::E5#embed_passage(text)` prepends `"passage: "` | Pure Ruby: `@embedder.embed(["passage: #{text}"])[0]` |
| API-06 | `GTE.configure { |c| c.model_path = "..." }` sets global defaults; `GTE.default` returns memoized embedder | Pure Ruby module-level Configuration class pattern |
| API-07 | Embedding output is L2-normalized by default | Rust: `norm = row.mapv(|x| x*x).sum().sqrt(); row / norm`; skip if `norm == 0.0` |
</phase_requirements>

---

## Summary

Phase 3 bridges the Phase 2 Rust inference core to Ruby via magnus FFI bindings and a pure Ruby API layer. The Rust side wraps `Embedder` in a `#[wrap]` struct with `free_immediately` and `size`, exposes it as `GTE::Embedder` in Ruby, releases the GVL during `session.run()` using the rb-sys raw `rb_thread_call_without_gvl` binding (magnus 0.8.x does NOT expose a high-level `call_without_gvl` method), and converts all errors to `GTE::Error`. The Ruby side adds family classes (E5, CLIP, Siglip2) as pure Ruby wrappers over `GTE::Embedder`, plus prefix semantics and a global configuration module.

The key technical insight is that magnus 0.8.2 does NOT include a `thread_call_without_gvl` method in its `Ruby` struct API. The CONTEXT.md D-02 decision references this wrapper, but it does not exist in the current magnus version. The actual approach is to call `rb_sys::rb_thread_call_without_gvl` directly via the rb-sys generated bindings — which are always present since rb-sys is a build dependency. This requires an `unsafe` block but follows the same pattern as every other non-magnus Ruby extension that releases the GVL.

L2 normalization must be added to `embedder.rs` before the FFI return — it was explicitly deferred from Phase 2. The `Array2<f32>` rows are normalized in-place before conversion to Ruby `Array<Array<Float>>`.

**Primary recommendation:** Use `#[wrap(class = "GTE::Embedder", free_immediately, size)]` on a struct wrapping `Arc<Embedder>`; release GVL with `unsafe { rb_sys::rb_thread_call_without_gvl(...) }` wrapping only the `session.run()` call; build all three family classes as pure Ruby files.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `magnus` | `0.8` (pinned in Cargo.toml; 0.8.2 available) | Ruby C extension bindings — `#[wrap]`, `function!`, `method!`, error types | Project decision; nero reference implementation |
| `rb-sys` | `0.9` (`stable-api-compiled-fallback`) | Generated Ruby C bindings including `rb_thread_call_without_gvl` | Required for GVL release; build toolchain bridge |
| `ndarray` | `0.16.0` | Array2<f32> L2 normalization before FFI return | Already in Cargo.toml from Phase 2 |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `rspec` | current (3.13.x in Gemfile.lock) | Ruby test framework | All Ruby API spec files |
| `rspec-benchmark` | `0.6.0` | Benchmark assertions (Phase 4) | Not needed for Phase 3 tests |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Raw `rb_thread_call_without_gvl` via rb-sys | `lucchetto` crate `#[without_gvl]` macro | lucchetto is a third-party crate not already in the dependency tree; raw rb-sys binding is already available and well understood |
| Pure Ruby L2 normalization | Rust L2 normalization | D-08 locks Rust; Ruby normalization adds per-float Ruby object overhead |

---

## Architecture Patterns

### Recommended Project Structure

```
ext/gte/src/
├── lib.rs              # #[magnus::init] — registers GTE::Embedder class + methods
├── ruby_embedder.rs    # NEW: #[wrap] struct RbEmbedder + FFI methods
├── embedder.rs         # Existing — add normalize() + L2 normalization
├── error.rs            # Add From<GteError> for magnus::Error (feature-gated)
├── model_config.rs     # Existing — unchanged
├── session.rs          # Existing — unchanged
└── tokenizer.rs        # Existing — unchanged

lib/
├── gte.rb              # Add require_relative for family classes
├── gte/
│   ├── version.rb      # Existing
│   ├── e5.rb           # NEW: GTE::E5 class
│   ├── clip.rb         # NEW: GTE::CLIP class
│   ├── siglip2.rb      # NEW: GTE::Siglip2 class
│   └── configuration.rb # NEW: GTE::Configuration + module-level configure/default

spec/
├── spec_helper.rb      # Existing — minimal, already require "gte"
├── gte/
│   ├── embedder_spec.rb    # BIND-01, BIND-02, BIND-03, BIND-04
│   ├── e5_spec.rb          # API-01, API-04, API-05
│   ├── clip_spec.rb        # API-02
│   ├── siglip2_spec.rb     # API-03
│   └── configuration_spec.rb # API-06
└── support/
    └── fixtures.rb     # Shared model path helpers for specs (skips if no fixture)
```

### Pattern 1: `#[wrap]` Struct with Arc

The nero reference (`impl/nero/ext/nero/src/lib.rs`) wraps `Arc<GLiNER>` in a struct:

```rust
// Source: impl/nero/ext/nero/src/lib.rs (confirmed)
#[wrap(class = "Nero::Model", free_immediately, size)]
struct Nero {
    model: Arc<GLiNER<SpanMode>>,
}
```

For GTE, the pattern mirrors this directly:

```rust
// Source: Derived from nero reference + magnus 0.8.2 typed_data.rs (confirmed)
#[cfg(feature = "ruby-ffi")]
#[wrap(class = "GTE::Embedder", free_immediately, size)]
struct RbEmbedder {
    inner: Arc<crate::embedder::Embedder>,
}
```

`free_immediately` is safe when the wrapped type does not hold Ruby objects — `Embedder` holds only Rust-owned `Tokenizer`, `Session`, and `ModelConfig`, so this is always safe.

`Arc` is required because the `#[wrap]` struct must be `Send` (magnus enforces this via the `TypedData` bound `Self: Send`). `Embedder` itself contains `Session` which is `unsafe impl Send` in ort 2.0.0-rc.9, so `Arc<Embedder>` is `Send + Sync`.

### Pattern 2: GVL Release via rb-sys Raw Binding

Magnus 0.8.2 does NOT expose `thread_call_without_gvl` as a high-level method. The rb-sys generated bindings at build time always include this symbol (confirmed present in `impl/nero/target/release/build/rb-sys-7f2a1b5210502b5d/out/bindings-*.rs`).

```rust
// Source: rb-sys generated bindings — verified in impl/nero build output
// rb_thread_call_without_gvl signature (from generated binding):
//   pub fn rb_thread_call_without_gvl(
//       func: Option<unsafe extern "C" fn(*mut c_void) -> *mut c_void>,
//       data1: *mut c_void,
//       ubf: rb_unblock_function_t,
//       data2: *mut c_void,
//   ) -> *mut c_void;

use std::os::raw::c_void;

struct InferArgs {
    session_ptr: *const ort::session::Session,
    tokenized_ptr: *const crate::tokenizer::Tokenized,
    config_ptr: *const crate::model_config::ModelConfig,
    result: Option<Result<ndarray::Array2<f32>, crate::error::GteError>>,
}

unsafe extern "C" fn run_without_gvl(data: *mut c_void) -> *mut c_void {
    let args = &mut *(data as *mut InferArgs);
    args.result = Some(crate::session::run_session(
        &*args.session_ptr,
        &*args.tokenized_ptr,
        &*args.config_ptr,
    ));
    std::ptr::null_mut()
}

// Inside RbEmbedder::embed() FFI method, after tokenization:
let mut args = InferArgs { /* ... */ result: None };
unsafe {
    rb_sys::rb_thread_call_without_gvl(
        Some(run_without_gvl),
        &mut args as *mut InferArgs as *mut c_void,
        None,  // UBF — RUBYVMJMP_TAG_NONE: no cancellation
        std::ptr::null_mut(),
    );
}
let embeddings = args.result.unwrap()?;
```

**Note on `ubf` (unblocking function):** Passing `None` means `Thread.kill` cannot interrupt an in-progress inference. For Phase 3 this is acceptable — inference runs in milliseconds and the alternative (implementing a cancellation mechanism for ORT) is out of scope.

### Pattern 3: Error Conversion — `From<GteError> for magnus::Error`

STATE.md records the Phase 2 decision: "GteError is Rust-internal only — Phase 3 adds From<GteError> for magnus::Error."

```rust
// Source: lib.rs pattern, feature-gated to avoid contaminating non-FFI builds
#[cfg(feature = "ruby-ffi")]
impl From<crate::error::GteError> for magnus::Error {
    fn from(e: crate::error::GteError) -> Self {
        // GTE::Error was defined in Phase 1 init() — safe to look up by class path
        let ruby = magnus::Ruby::get().expect("called from Ruby thread");
        let gte_error_class = ruby
            .class_path("GTE::Error")
            .expect("GTE::Error must be defined before embedder methods are called");
        magnus::Error::new(gte_error_class, e.to_string())
    }
}
```

This allows `?` to propagate GteErrors naturally in FFI methods that return `Result<Value, Error>`.

### Pattern 4: RbEmbedder::new — Keyword Arguments

Magnus receives Ruby keyword arguments via the `scan_args` API or by defining the Rust method to accept a Ruby Hash. For `GTE::Embedder.new(tokenizer_path:, model_path:, config:)`:

```rust
// Source: magnus scan_args docs + nero pattern (confirmed)
impl RbEmbedder {
    fn new(
        ruby: &Ruby,
        tokenizer_path: String,
        model_path: String,
        config: magnus::RHash,  // Ruby Hash with :max_length, :output_tensor, :mode, :with_type_ids
    ) -> Result<Self, Error> {
        let model_config = model_config_from_rhash(ruby, config)?;
        let embedder = Embedder::new(tokenizer_path, model_path, model_config)
            .map_err(magnus::Error::from)?;
        Ok(RbEmbedder { inner: Arc::new(embedder) })
    }
}
```

**Alternative:** Expose separate `config:` as a symbol string (`"e5"`, `"clip"`, `"siglip2"`) and map to `ModelConfig` factory methods. This simplifies the Ruby API since family classes call with a known config name.

### Pattern 5: L2 Normalization in Rust

Added to `embedder.rs` before the `Array2<f32>` is returned:

```rust
// Source: ndarray 0.16 docs + D-08
fn normalize_l2(mut embeddings: ndarray::Array2<f32>) -> ndarray::Array2<f32> {
    for mut row in embeddings.rows_mut() {
        let norm = row.mapv(|x| x * x).sum().sqrt();
        if norm > 0.0 {
            row /= norm;
        }
        // If norm == 0.0: leave as zero vector (avoids NaN)
    }
    embeddings
}
```

### Pattern 6: RArray → Vec<String> and Array2<f32> → RArray

```rust
// Magnus RArray iteration — confirmed available in magnus 0.8
fn embed(ruby: &Ruby, rb_self: &RbEmbedder, texts: RArray) -> Result<RArray, Error> {
    let texts: Vec<String> = texts.to_vec()?;

    // ... GVL release + inference ...

    // Convert Array2<f32> to RArray of RArray
    let outer = ruby.ary_new_capa(embeddings.nrows());
    for row in embeddings.rows() {
        let inner = ruby.ary_new_capa(row.len());
        for &val in row.iter() {
            inner.push(val)?;  // f32 → Ruby Float
        }
        outer.push(inner)?;
    }
    Ok(outer)
}
```

### Pattern 7: Pure Ruby Family Classes

```ruby
# lib/gte/e5.rb — Source: D-05, D-06 from CONTEXT.md
module GTE
  class E5
    def initialize(model_path:, tokenizer_path: nil)
      resolved_tokenizer = tokenizer_path || File.join(File.dirname(model_path), "tokenizer.json")
      @embedder = GTE::Embedder.new(
        tokenizer_path: resolved_tokenizer,
        model_path: model_path,
        config: "e5"
      )
    end

    def embed(texts)
      @embedder.embed(Array(texts))
    end

    def embed_query(text)
      @embedder.embed(["query: #{text}"]).first
    end

    def embed_passage(text)
      @embedder.embed(["passage: #{text}"]).first
    end
  end
end
```

```ruby
# lib/gte/configuration.rb — Source: D-07 from CONTEXT.md
module GTE
  class Configuration
    attr_accessor :model_path, :tokenizer_path, :model_family

    def initialize
      @model_family = :e5
    end
  end

  class << self
    def configure
      yield config
    end

    def config
      @config ||= Configuration.new
    end

    def default
      @default ||= begin
        klass = const_get(config.model_family.to_s.upcase)
        klass.new(
          model_path: config.model_path,
          tokenizer_path: config.tokenizer_path
        )
      end
    end

    def reset_default!
      @default = nil
    end
  end
end
```

### Anti-Patterns to Avoid

- **Using `ruby.exception_runtime_error()` for GTE errors:** nero uses RuntimeError but D-04 explicitly requires `GTE::Error < StandardError`. Always look up `GTE::Error` class.
- **Calling Ruby API inside `rb_thread_call_without_gvl` callback:** The callback runs without the GVL. Never push to RArray, raise Magnus errors, or call any `rb_*` API inside the `run_without_gvl` extern function.
- **Passing `Arc<Embedder>` across FFI without Arc clone:** Each Ruby `GTE::Embedder` instance holds its own `Arc` clone. The `Arc` clone keeps the inner `Embedder` alive for the lifetime of that Ruby object.
- **Returning `SessionOutputs` from `run_session` (already avoided in Phase 2):** SessionOutputs borrows Session; confirmed in session.rs comment.
- **Using `OnceCell` singleton:** STATE.md and CONTEXT.md both explicitly prohibit this; multiple model instances per process is a goal.
- **Forgetting to require family files in lib/gte.rb:** Add `require_relative "gte/e5"` etc. or the classes will not be autoloaded.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Ruby ↔ Rust type coercion | Manual `VALUE` pointer juggling | `magnus` `TryConvert`, `IntoValue` | magnus handles GC safety, type checking, UTF-8 validation |
| GVL release | Manual `extern "C"` wrapper plumbing | rb-sys `rb_thread_call_without_gvl` binding | Already generated — correct signature, handles GVL acquire/release cycle |
| Ruby Hash keyword args | Manual `rb_hash_aref` calls | `magnus::RHash` + `aref()` or `scan_args` | Magnus provides type-safe hash access |
| L2 normalization | Ruby-side dot product/sqrt | ndarray row normalization in Rust | Avoids Ruby object allocation per float; D-08 |
| Error class lookup | Hardcoded VALUE pointer | `ruby.class_path("GTE::Error")` or `From<GteError>` impl | Type-safe, refactoring-friendly |

**Key insight:** The entire FFI plumbing (type conversion, GC safety, exception propagation) is handled by magnus. Only the GVL release requires reaching into rb-sys raw bindings, and even that is a 10-line pattern.

---

## Common Pitfalls

### Pitfall 1: magnus 0.8 Has No `thread_call_without_gvl` High-Level API

**What goes wrong:** Developer looks for `ruby.thread_call_without_gvl()` based on CONTEXT.md D-02 wording ("the magnus-provided safe wrapper") — this method does not exist in magnus 0.8.2.

**Why it happens:** CONTEXT.md describes intent, not current API reality. Magnus lib.rs line 1509 comments `rb_thread_call_without_gvl` as "not wrapped" (comment-only, no `!` prefix means NOT documented as exposed).

**How to avoid:** Use `unsafe { rb_sys::rb_thread_call_without_gvl(...) }` directly. The rb-sys binding is always generated since rb-sys is already a required build dependency.

**Warning signs:** Compiler error "no method named `thread_call_without_gvl` found for type `&Ruby`"

### Pitfall 2: `Session` Sync Warning for Non-CPU Execution Providers

**What goes wrong:** ORT source includes a comment: "Allowing Sync segfaults with CUDA, DirectML, and seemingly any EP other than the CPU EP." Phase 3 uses CPU-only ORT.

**Why it happens:** ORT marks `Session: Sync` with a caveat. Phase 3 is CPU-only so this is safe.

**How to avoid:** Keep Phase 3 CPU-only (already the plan). Do not add GPU EP support.

**Warning signs:** Only relevant if execution providers are added in future phases.

### Pitfall 3: `feature = "ruby-ffi"` Gate Must Wrap All magnus/rb-sys Imports

**What goes wrong:** Adding `use rb_sys::...` or `use magnus::...` at the top of `embedder.rs` without feature gate breaks `cargo test --no-default-features` (integration tests run without Ruby runtime).

**Why it happens:** Phase 2 established the `ruby-ffi` feature gate pattern. All Phase 3 Rust code that touches magnus or rb-sys must live in files guarded by `#[cfg(feature = "ruby-ffi")]` or in `lib.rs` / `ruby_embedder.rs` which are only compiled with the feature.

**How to avoid:** Put all FFI code in `src/ruby_embedder.rs` gated by `#[cfg(feature = "ruby-ffi")]`. The `From<GteError> for magnus::Error` impl must also be feature-gated.

**Warning signs:** `cargo test --no-default-features` fails with "unresolved import `magnus`"

### Pitfall 4: Arc Clone Overhead vs. Deep Copy

**What goes wrong:** Developer copies the Embedder instead of cloning the Arc when a new Ruby object is created — this re-tokenizes, re-creates the ORT session, etc.

**Why it happens:** Confusion between `Arc::clone()` (cheap reference count increment) and value clone.

**How to avoid:** `RbEmbedder::new` wraps once: `Arc::new(embedder)`. Any sharing between Ruby objects uses `Arc::clone(&self.inner)` — but in Phase 3 each Ruby `GTE::Embedder` instance is independent (no sharing between instances is needed).

**Warning signs:** Construction time scales linearly with Ruby object count.

### Pitfall 5: GTE::Error Class Lookup Timing

**What goes wrong:** `From<GteError> for magnus::Error` calls `ruby.class_path("GTE::Error")` but if called during `init()` before the error class is defined, it panics.

**Why it happens:** `init()` defines `GTE::Error` first, then registers embedder methods. Errors only surface at method call time (after init), so the ordering is correct.

**How to avoid:** Define `GTE::Error` as the FIRST statement in `init()` (already done in Phase 1). The `From` impl is only called during method execution, never during registration.

**Warning signs:** Panic "GTE::Error must be defined before embedder methods are called" on first method call.

### Pitfall 6: RSpec Tests Require Actual Model Files

**What goes wrong:** `spec/gte/embedder_spec.rb` calls `GTE::Embedder.new(tokenizer_path:, model_path:)` and fails immediately because no fixture model exists in CI.

**Why it happens:** ONNX models are large binary files not committed to git. Phase 2 handled this for Rust by marking all tests `#[ignore]`.

**How to avoid:** Use `skip "requires model fixture"` in specs that need real models, or use a `skip_unless_fixture` helper. Tests that verify Ruby class structure (module, method existence, error type) should run without fixtures.

**Warning signs:** CI fails with "No such file or directory — tokenizer.json"

### Pitfall 7: `embed` Return Type for Single vs. Batch Input

**What goes wrong:** BIND-02 says single string input should return `Array<Float>` (not `Array<Array<Float>>`). But the Rust layer always returns `Array<Array<Float>>`.

**Why it happens:** Requirements spec says "batch or single string." Implementing the unwrapping in Rust complicates the FFI method signature.

**How to avoid:** Keep Rust FFI always returning `Array<Array<Float>>`. Handle single-string unwrapping in the Ruby layer (family class methods already do this: `@embedder.embed(["query: #{text}"]).first`). `GTE::Embedder#embed` always returns nested array; family class convenience methods return flat array for single inputs.

---

## Code Examples

### Complete `ruby_embedder.rs` Outline

```rust
// Source: nero reference + magnus 0.8.2 typed_data.rs + rb-sys generated bindings
#![cfg(feature = "ruby-ffi")]

use std::os::raw::c_void;
use std::sync::Arc;
use magnus::{function, method, prelude::*, wrap, Error, RArray, Ruby};
use crate::embedder::Embedder;
use crate::error::GteError;

#[wrap(class = "GTE::Embedder", free_immediately, size)]
pub struct RbEmbedder {
    inner: Arc<Embedder>,
}

impl RbEmbedder {
    pub fn rb_new(
        ruby: &Ruby,
        tokenizer_path: String,
        model_path: String,
        config_name: String,   // "e5" | "clip" | "siglip2"
    ) -> Result<Self, Error> {
        use crate::model_config::ModelConfig;
        let config = match config_name.as_str() {
            "e5"       => ModelConfig::e5(),
            "clip"     => ModelConfig::clip(),
            "siglip2"  => ModelConfig::siglip2(),
            other      => return Err(Error::new(
                ruby.exception_argument_error(),
                format!("unknown config: {other}; expected 'e5', 'clip', or 'siglip2'"),
            )),
        };
        let embedder = Embedder::new(tokenizer_path, model_path, config)
            .map_err(Error::from)?;
        Ok(RbEmbedder { inner: Arc::new(embedder) })
    }

    pub fn rb_embed(ruby: &Ruby, rb_self: &Self, texts: RArray) -> Result<RArray, Error> {
        let texts: Vec<String> = texts.to_vec()?;
        let tokenized = rb_self.inner.tokenize(&texts).map_err(Error::from)?;

        // Release GVL for inference only
        let embeddings = unsafe {
            struct Args {
                session: *const ort::session::Session,
                tokenized: *const crate::tokenizer::Tokenized,
                config: *const crate::model_config::ModelConfig,
                result: Option<Result<ndarray::Array2<f32>, GteError>>,
            }
            unsafe extern "C" fn run_no_gvl(ptr: *mut c_void) -> *mut c_void {
                let args = &mut *(ptr as *mut Args);
                args.result = Some(crate::session::run_session(
                    &*args.session,
                    &*args.tokenized,
                    &*args.config,
                ));
                std::ptr::null_mut()
            }
            let mut args = Args {
                session: rb_self.inner.session_ptr(),
                tokenized: &tokenized,
                config: rb_self.inner.config_ptr(),
                result: None,
            };
            rb_sys::rb_thread_call_without_gvl(
                Some(run_no_gvl),
                &mut args as *mut Args as *mut c_void,
                None,
                std::ptr::null_mut(),
            );
            args.result.unwrap().map_err(Error::from)?
        };

        // L2 normalize then convert to RArray<RArray<Float>>
        let normalized = crate::embedder::normalize_l2(embeddings);
        array2_to_rarray(ruby, normalized)
    }
}

fn array2_to_rarray(ruby: &Ruby, arr: ndarray::Array2<f32>) -> Result<RArray, Error> {
    let outer = ruby.ary_new_capa(arr.nrows());
    for row in arr.rows() {
        let inner = ruby.ary_new_capa(row.len());
        for &val in row.iter() {
            inner.push(val)?;
        }
        outer.push(inner)?;
    }
    Ok(outer)
}

pub fn register(ruby: &Ruby) -> Result<(), Error> {
    let module = ruby.define_module("GTE")?;
    let class = module.define_class("Embedder", ruby.class_object())?;
    class.define_singleton_method("new", function!(RbEmbedder::rb_new, 3))?;
    class.define_method("embed", method!(RbEmbedder::rb_embed, 1))?;
    Ok(())
}
```

**Note on `session_ptr()` and `config_ptr()`:** `Embedder` needs to expose the session and config by pointer for the GVL callback. This requires adding accessor methods to `Embedder` that return raw pointers — or restructuring so `RbEmbedder::rb_embed` takes ownership of the inference call differently. An alternative is to expose a `tokenize()` method and a separate `run_session_raw()` method on `Embedder` that the FFI layer calls. The exact split is at the implementer's discretion.

### `init()` Function Integration

```rust
// Source: nero reference + Phase 1 lib.rs
#[cfg(feature = "ruby-ffi")]
#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    let module = ruby.define_module("GTE")?;
    module.define_error("Error", ruby.exception_standard_error())?;  // Phase 1, keep

    std::panic::set_hook(/* ... Phase 1, keep */);

    // Phase 3: register Embedder class
    crate::ruby_embedder::register(ruby)?;

    Ok(())
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `rutie` for Rust Ruby bindings | `magnus` 0.8 | ~2022 | magnus is maintained; rutie is not |
| `Thread::call_without_gvl` in rutie | Raw `rb_thread_call_without_gvl` via rb-sys | N/A — magnus never added high-level wrapper | Must use unsafe block |
| Manual `rb_data_typed_object_wrap` | `#[wrap]` or `#[derive(TypedData)]` macro | magnus 0.5+ | Macro generates all TypedData boilerplate |

**Not deprecated but important:**
- `free_immediately`: Still the correct choice when the wrapped type holds no Ruby objects (pure Rust data). Confirmed safe for `RbEmbedder`.
- `rb_nogvl` vs `rb_thread_call_without_gvl`: `rb_nogvl` is a newer variant that accepts flags. For Phase 3 the simpler `rb_thread_call_without_gvl` is sufficient.

---

## Open Questions

1. **Embedder internals access for GVL split**
   - What we know: `Embedder::embed()` combines tokenization + session.run() in one call. Phase 3 needs to split them so only `session.run()` happens outside the GVL.
   - What's unclear: Whether to add a `tokenize()` / `run_inference()` pair to `Embedder`, or access session/config via raw pointers from `RbEmbedder`.
   - Recommendation: Add `pub fn tokenize(&self, texts: &[String]) -> Result<Tokenized>` and `pub fn run(&self, tokenized: &Tokenized) -> Result<Array2<f32>>` to `Embedder` — cleaner than pointer exposure. Both are already composed inside `embed()`.

2. **config: Ruby API — string name vs. Hash**
   - What we know: D-05 says family classes use family-specific defaults. The Rust FFI takes a `config` argument.
   - What's unclear: Whether `GTE::Embedder.new` should accept a string config name (`"e5"`) or a keyword hash with individual fields.
   - Recommendation: String config name (`"e5"`, `"clip"`, `"siglip2"`) — simpler API surface; family classes always call with the right name; advanced users can still get to ModelConfig fields if exposed later.

3. **Siglip2 output_tensor name**
   - What we know: Phase 2 left this as `"TODO_inspect_siglip2_onnx_output_tensor_name"` — LOW confidence.
   - What's unclear: The actual output tensor name of the Siglip2 ONNX text encoder export.
   - Recommendation: Mark `GTE::Siglip2.new` specs as pending/skipped until a fixture model is inspected. The Ruby class can be created with a placeholder, and the Rust `ModelConfig::siglip2()` remains a TODO.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Rust (cargo) | Extension compile | Check | — | Required — no fallback |
| Ruby >= 3.2 | All Ruby specs | via nix develop | 3.4.2 (Gemfile.lock) | None |
| rb-sys generated bindings | GVL release | Built at compile time | 0.9.126 (Gemfile.lock) | None |
| ONNX model fixtures | Integration specs | NOT in repo | — | Skip specs with `skip` guard |

**Missing dependencies with fallback:**
- ONNX model fixtures: All specs that call `embed()` with real data should guard with `skip "requires model fixture"` or detect fixture absence.

---

## Validation Architecture

Validation is explicitly disabled in config (`workflow.nyquist_validation: false`). Skipping this section.

---

## Project Constraints (from CLAUDE.md)

The following directives from CLAUDE.md must be honored by the planner:

- **Tech stack**: Ruby >= 3.2, Rust edition 2021, ONNX Runtime via `ort` crate — no deviations
- **Build**: flake.nix for reproducible dev; `ORT_STRATEGY=system` in Nix shell — do not add `ORT_STRATEGY=download`
- **Scope**: Minimal — validate embedding speed before expanding features
- **What NOT to use**: `rutie`, raw `rb-sys` for binding code logic (use magnus for bindings), `orp` crate, `OnceCell` singleton, Ruby `onnxruntime` gem, Ruby `tokenizers` gem
- **GTE::Error**: Must inherit `StandardError` (not RuntimeError) — `exception_standard_error()`, NOT `exception_runtime_error()`
- `ort` must remain pinned to `=2.0.0-rc.9`; `ort-sys` must remain pinned to `=2.0.0-rc.9`
- `ruby-ffi` feature gate must be maintained — `cargo test --no-default-features` must stay green

---

## Sources

### Primary (HIGH confidence)
- `impl/nero/ext/nero/src/lib.rs` — `#[wrap]`, `function!`, `method!`, `free_immediately`, `Arc` pattern (confirmed local file)
- `~/.cargo/registry/src/.../magnus-0.8.2/src/typed_data.rs` — `free_immediately` flag, `DataTypeFunctions`, `TypedData` trait bounds (confirmed local source)
- `~/.cargo/registry/src/.../magnus-0.8.2/src/lib.rs` lines 1509-1511 — `rb_thread_call_without_gvl` NOT exposed by magnus (confirmed by comment-only entries without `!`)
- `impl/nero/target/release/build/rb-sys-.../out/bindings-0.9.124-mri-arm64-darwin24-3.4.2.rs` lines 8424-8433 — exact `rb_thread_call_without_gvl` signature from rb-sys bindgen output (confirmed local file)
- `~/.cargo/registry/src/.../ort-2.0.0-rc.9/src/session/mod.rs` lines 518-521 — `Session` is `Send + Sync` (confirmed local source)
- `ext/gte/src/embedder.rs` — `Embedder` struct, `embed()` signature (confirmed local file)
- `ext/gte/src/error.rs` — `GteError` variants (confirmed local file)
- `ext/gte/src/model_config.rs` — `ModelConfig` factory methods (confirmed local file)

### Secondary (MEDIUM confidence)
- [magnus docs.rs Ruby struct API](https://docs.rs/magnus/0.8.1/magnus/struct.Ruby.html) — thread methods listed; `thread_call_without_gvl` not present (WebFetch verified)
- [lucchetto crate](https://github.com/Maaarcocr/lucchetto) — alternative `#[without_gvl]` macro; not recommended over direct rb-sys for this project

### Tertiary (LOW confidence)
- WebSearch results on `rb_thread_call_without_gvl` patterns — consistent with rb-sys binding signature found in local files

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all libraries confirmed in Cargo.toml and Gemfile.lock
- Architecture: HIGH — nero reference + magnus source + existing Phase 2 code provide complete picture
- GVL release mechanism: HIGH — confirmed `rb_thread_call_without_gvl` in rb-sys generated bindings; confirmed magnus 0.8.2 does NOT expose a high-level wrapper
- Pitfalls: HIGH — discovered via direct source inspection (not just documentation)
- Siglip2 output_tensor: LOW — tracked blocker from Phase 2; no model to inspect

**Research date:** 2026-04-07
**Valid until:** 2026-05-07 (stable libraries; 30-day window)
