# Phase 3: Ruby Bindings + API - Context

**Gathered:** 2026-04-07
**Status:** Ready for planning

<domain>
## Phase Boundary

Expose the Phase 2 Rust inference core to Ruby via magnus FFI bindings, and build the ergonomic Ruby API layer on top — including family convenience classes (E5, CLIP, Siglip2), prefix semantics (embed_query/embed_passage), and global configuration. By the end of this phase, a developer can call `GTE::E5.new(model_path:).embed_query(text)` from Ruby and receive an L2-normalized `Array<Float>`.

Requirements in scope: BIND-01, BIND-02, BIND-03, BIND-04, API-01, API-02, API-03, API-04, API-05, API-06, API-07

</domain>

<decisions>
## Implementation Decisions

### GVL + Thread Safety
- **D-01:** GVL is released **only during `session.run`** — the ORT inference call is the bottleneck; tokenization stays within the GVL (fast and tokenizer internals may not be `Send`)
- **D-02:** GVL release uses `ruby.thread_call_without_gvl(|| ...)` — the magnus-provided safe wrapper for `rb_thread_call_without_gvl`; no manual unsafe FFI
- **D-03:** `Session` is wrapped in `Arc` so multiple Ruby threads can share the same `Embedder` concurrently without blocking. The `#[wrap]` struct uses `free_immediately` (magnus pattern from nero reference)
- **D-04:** Error conversion at FFI boundary: `GteError` → `GTE::Error` (already defined in Phase 1) via `Error::new(gte_error_class, msg)` in every Rust FFI method; never leak Rust error strings as RuntimeError

### Ruby API Design
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

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ext/gte/src/lib.rs` — Already has `#[cfg(feature = "ruby-ffi")]` gate and `#[magnus::init]` skeleton; Phase 3 fills in the class/method registration
- `ext/gte/src/embedder.rs` — `Embedder::new(tokenizer_path, model_path, config) -> Result<Embedder>` and `embed(texts) -> Result<Array2<f32>>` — the Rust API Phase 3 wraps
- `impl/nero/ext/nero/src/lib.rs` — Reference for `#[wrap]`, `function!`, `method!` patterns, `free_immediately`, error conversion
- `lib/gte.rb` — Already `require "gte/gte"` (native ext) and `require_relative "gte/version"`
- `lib/gte/version.rb` — VERSION constant already exists

### Established Patterns
- nero's `#[wrap(class = "Nero::Model", free_immediately, size)]` — apply to `GTE::Embedder` struct
- magnus method registration: `module.define_singleton_method("method_name", function!(Struct::method, arity))`
- Error conversion in nero: `Error::new(ruby.get_inner_ref(&gte_error_class), msg.to_string())` pattern
- `ORT_STRATEGY=system` is set via Nix — no change needed to flake.nix

### Integration Points
- `ext/gte/src/embedder.rs` — `Embedder` struct gains a `#[wrap]` attribute and is exposed to Ruby
- `ext/gte/src/lib.rs` — `init()` function registers all classes, methods, and module functions
- `lib/gte.rb` — May need additional `require_relative` for family class files
- `spec/` — RSpec tests will exercise the Ruby API end-to-end (requires model fixtures)

</code_context>

<specifics>
## Specific Ideas

- The `thread_call_without_gvl` release must go **inside** the Rust FFI method, wrapping just the `self.session.run(...)` call — not the entire `embed()` method (tokenization is fast)
- L2 normalization: for each row, compute `norm = sqrt(sum of squares)`, divide each element by `norm`. Skip if `norm == 0.0` to avoid NaN.
- The nero reference uses `OnceCell` for a singleton — GTE explicitly does NOT do this (multiple models per process is a goal)

</specifics>

<deferred>
## Deferred Ideas

- Image embeddings (CLIP/Siglip2 vision) — out of scope for v1, text-only
- Model downloading/management — user provides model path
- Streaming/async embed — synchronous only for v1
- RubyGems.org publish — Phase 4 concern

</deferred>

---

*Phase: 03-ruby-bindings-+-api*
*Context gathered: 2026-04-07*
