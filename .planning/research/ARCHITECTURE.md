# Architecture Patterns

**Domain:** Ruby gem with Rust cdylib extension for ONNX text embeddings
**Researched:** 2026-04-06
**Confidence:** HIGH — derived directly from two reference implementations in `impl/`

---

## Recommended Architecture

The gem is a thin Ruby wrapper over a Rust cdylib extension. The Rust extension
owns all computation: tokenization, session management, ONNX inference, and
output conversion. Ruby handles API ergonomics, configuration, and type coercion.

```
┌─────────────────────────────────────────────────────────┐
│  Ruby Layer                                             │
│                                                         │
│  GTE                    (public API, config, defaults)  │
│  GTE::Embedder          (instance: model path, params)  │
│  GTE::Embedder::Embed   (value object: Vec<Vec<f32>>)   │
└────────────────────────┬────────────────────────────────┘
                         │  magnus FFI
┌────────────────────────▼────────────────────────────────┐
│  Rust Extension  (ext/gte/src/lib.rs)                   │
│                                                         │
│  GTE::Embedder  (magnus #[wrap] struct)                 │
│    ├── EmbedderInner                                    │
│    │     ├── ort::Session          (ONNX model)         │
│    │     └── tokenizers::Tokenizer (HF tokenizer)       │
│    └── fn embed(texts: Vec<String>) -> Vec<Vec<f32>>    │
│                                                         │
│  ModelConfig   (params: max_length, output_id, mode,    │
│                  precision, token_types, positions)     │
└─────────────────────────────────────────────────────────┘
```

---

## Component Boundaries

| Component | Layer | Responsibility | Communicates With |
|-----------|-------|---------------|-------------------|
| `GTE` (Ruby module) | Ruby | Public API surface, config accessor, `default` instance | `GTE::Embedder` (Ruby) |
| `GTE::Embedder` (Ruby) | Ruby | Wraps Rust struct, coerces input/output types | `GTE::Embedder` (Rust, via magnus) |
| `GTE::Embedder` (Rust `#[wrap]` struct) | Rust | Owns `ort::Session` + `tokenizers::Tokenizer`, runs pipeline | `ort`, `tokenizers` crates |
| `ModelConfig` | Rust | Carries per-model parameters (output tensor name, extraction mode, precision, optional tensor inputs) | `EmbedderInner` constructor |
| `ort::Session` | Rust (external) | Executes ONNX graph | ONNX Runtime dylib |
| `tokenizers::Tokenizer` | Rust (external) | Tokenizes string input to i64 arrays | `ort::Session` indirectly via tensor prep |

**Boundary rule:** No ORT or tokenizer types cross the Ruby/Rust boundary. Only
`Vec<String>` goes in and `Vec<Vec<f32>>` comes out. All tensor housekeeping stays
in Rust.

---

## Data Flow

```
Ruby Array<String>
  │
  │  magnus RArray → Vec<String>
  ▼
Rust: tokenizers::Tokenizer::encode_batch(texts)
  │  → Tokenized { input_ids: Array2<i64>,
  │                attn_masks: Array2<i64>,
  │                token_type_ids?: Array2<i64>,
  │                position_ids?: Array2<i64> }
  ▼
Rust: assemble SessionInputs (HashMap<&str, ORT Value>)
  │  always:   "input_ids", "attention_mask"
  │  optional: "token_type_ids" (E5), "position_ids" (Siglip2/CLIP)
  ▼
Rust: ort::Session::run(inputs)
  │  → ORT outputs map
  ▼
Rust: extract tensor by output_id ("last_hidden_state" or "sentence_embedding")
  │  → ndarray Array3<f32> [batch, seq_len, hidden_dim]
  │       or Array2<f32>   [batch, hidden_dim]  (raw mode)
  ▼
Rust: EmbeddingsExtractor — apply ExtractorMode
  │  Token(0): slice [:, 0, :] → Array2<f32> [batch, hidden_dim]   (E5 CLS token)
  │  Raw:      reshape directly → Array2<f32> [batch, hidden_dim]   (Siglip2/CLIP)
  ▼
Rust: convert Array2<f32> rows → Vec<Vec<f32>>
  │
  │  magnus Vec<Vec<f32>> → RArray<RArray<Float>>
  ▼
Ruby Array<Array<Float>>
```

---

## Model Type Handling: Unified Struct with Config, Not Separate Types

**Decision:** Use a single `EmbedderInner` struct parameterized by `ModelConfig`,
not separate structs per model family.

**Rationale from gte-rs:** The reference pipeline already proves this works cleanly.
All three model families (E5, CLIP, Siglip2) differ only in:

| Model family | `output_id` | `ExtractorMode` | `token_type_ids` | `position_ids` |
|-------------|-------------|-----------------|-----------------|---------------|
| E5 (text)   | `last_hidden_state` | `Token(0)` — CLS | false | false |
| Siglip2     | `last_hidden_state` or `sentence_embedding` | `Raw` | false | true |
| CLIP (text) | `last_hidden_state` | `Token(0)` | false | false |

`ModelConfig` (mirrors gte-rs `Parameters`) carries these four flags. The Ruby
layer exposes named presets:

```ruby
# Ruby convenience layer
module GTE
  MODELS = {
    e5:      ModelConfig.new(output_id: "last_hidden_state", mode: :token, token_idx: 0),
    siglip2: ModelConfig.new(output_id: "last_hidden_state", mode: :raw,   positions: true),
    clip:    ModelConfig.new(output_id: "last_hidden_state", mode: :token, token_idx: 0),
  }
end
```

The Rust struct needs no `match` dispatch — the config drives behavior entirely.
This is directly mirrored from `gte-rs/src/params/mod.rs`.

---

## Memory Management: Per-Instance, Eager Load

**Decision:** Load model eagerly on `Embedder.new`, hold per instance, no global
singleton.

**Rationale:**

nero uses a `OnceCell` singleton because NER models are expensive to load and users
typically want one global model. For an embedding gem:

- Users may legitimately load multiple models (E5 + CLIP in the same process).
- A singleton keyed only on the first call would silently ignore subsequent model paths.
- The Ruby `@default` pattern (`GTE.default`) can be implemented _in Ruby_ without
  forcing a global in Rust.

```rust
// Rust: no global OnceCell, plain struct ownership
#[wrap(class = "GTE::Embedder", free_immediately, size)]
struct Embedder {
    inner: EmbedderInner,  // owns Session + Tokenizer
}

impl Embedder {
    fn new(tokenizer_path: String, model_path: String, config: ...) -> Result<Self, Error> {
        Ok(Self { inner: EmbedderInner::new(tokenizer_path, model_path, config)? })
    }
}
```

```ruby
# Ruby: optional singleton pattern at the library level
module GTE
  def self.default
    @default ||= Embedder.new(config.tokenizer, config.model, config.model_type)
  end
end
```

The ORT Session itself is internally reference-counted by `ort`; `Arc<Session>` is
not needed here because the Ruby GC owns the lifetime of the `#[wrap]` struct.

**No LRU cache** — unlike nero's NER (where the same input + entities combination
recurs frequently), embedding requests are almost never identical. A cache would
waste memory without cache hits. Omit it.

---

## Rust Extension Internal Structure

```
ext/gte/
├── Cargo.toml          # cdylib, dependencies: magnus, rb-sys, ort, tokenizers, ndarray
├── build.rs            # VERSION sync check (mirrors nero pattern)
├── extconf.rb          # require "rb_sys/mkmf"; create_rust_makefile("gte/gte")
└── src/
    ├── lib.rs          # #[magnus::init], Ruby class/method registration
    ├── embedder.rs     # #[wrap] Embedder struct, new/embed methods
    ├── config.rs       # ModelConfig, ExtractorMode, Precision, preset builders
    ├── tokenizer.rs    # thin wrapper: tokenizers::Tokenizer → Tokenized tensors
    ├── pipeline.rs     # assemble SessionInputs, run session, extract embeddings
    └── error.rs        # GTE::Error Ruby exception class
```

### lib.rs skeleton

```rust
#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    let module = ruby.define_module("GTE")?;
    let cls = module.define_class("Embedder", ruby.class_object())?;
    cls.define_singleton_method("new", function!(Embedder::rb_new, 3))?;
    cls.define_method("embed", method!(Embedder::rb_embed, 1))?;
    Ok(())
}
```

### embedder.rs skeleton

```rust
#[wrap(class = "GTE::Embedder", free_immediately, size)]
pub struct Embedder {
    session: ort::Session,
    tokenizer: tokenizers::Tokenizer,
    config: ModelConfig,
}

impl Embedder {
    pub fn rb_new(
        tokenizer_path: String,
        model_path: String,
        config_hash: RHash,   // or named args
    ) -> Result<Self, Error> { ... }

    pub fn rb_embed(
        ruby: &Ruby,
        rb_self: &Self,
        texts: Vec<String>,
    ) -> Result<RArray, Error> {
        // tokenize → tensor → run → extract → Vec<Vec<f32>> → RArray
    }
}
```

---

## Build System Structure

```
gte/                         # gem root
├── VERSION                  # single source of version truth
├── Cargo.toml               # workspace root (optional, needed if multiple crates)
├── Gemfile
├── gte.gemspec
├── lib/
│   ├── gte.rb               # require "gte/gte" (native), then Ruby wrappers
│   ├── gte/
│   │   ├── version.rb
│   │   ├── config.rb
│   │   ├── embedder.rb      # Ruby facade over Rust GTE::Embedder
│   │   └── errors.rb
├── ext/
│   └── gte/
│       ├── Cargo.toml       # crate-type = ["cdylib"]
│       ├── build.rs         # VERSION sync assertion
│       ├── extconf.rb       # create_rust_makefile("gte/gte")
│       └── src/
│           └── (as above)
├── spec/
└── flake.nix
```

### extconf.rb (minimal, mirrors nero exactly)

```ruby
# frozen_string_literal: true
require "mkmf"
require "rb_sys/mkmf"
create_rust_makefile("gte/gte")
```

### build.rs (mirrors nero exactly)

```rust
fn main() {
    let version = std::fs::read_to_string("../../VERSION")
        .expect("VERSION file not found")
        .trim()
        .to_string();
    let cargo_version = env!("CARGO_PKG_VERSION");
    assert_eq!(version, cargo_version,
        "VERSION ({}) doesn't match Cargo.toml ({})", version, cargo_version);
    println!("cargo:rerun-if-changed=../../VERSION");
}
```

### Cargo.toml (extension crate)

```toml
[package]
name = "gte"
edition = "2021"
build = "build.rs"

[lib]
crate-type = ["cdylib"]

[dependencies]
magnus    = "0.8"
rb-sys    = { version = "0.9", features = ["stable-api-compiled-fallback"] }
ort       = "=2.0.0-rc.9"          # pin: matches gte-rs proven version
tokenizers = "0.21.0"               # matches gte-rs
ndarray   = "0.16.0"
half      = "2"                     # F16 precision support
```

**Note on `ort` version:** gte-rs pins `ort = "=2.0.0-rc.9"`. Pin to the same
version to avoid ABI mismatches with the ONNX Runtime dynamic library.

---

## Multi-Arch Binary Gem Packaging

### Strategy: rb-sys-dock + cross + GitHub Actions matrix

This is the same path nero takes. The toolchain is:

```
rb-sys-dock  → Docker-based cross compilation for Linux targets
cross        → Rust cross compilation wrapper
rake-compiler-dock → alternative (use rb-sys-dock; it integrates with rb-sys)
```

### Targets (v1 scope)

| Target | Platform | Tool |
|--------|----------|------|
| `aarch64-apple-darwin` | macOS ARM (dev machine) | native build |
| `x86_64-unknown-linux-gnu` | Linux x86_64 (CI/production) | rb-sys-dock |
| `aarch64-unknown-linux-gnu` | Linux ARM64 (Graviton/etc.) | rb-sys-dock |

### GitHub Actions matrix

```yaml
# .github/workflows/release.yml (structure)
jobs:
  build:
    strategy:
      matrix:
        include:
          - target: x86_64-unknown-linux-gnu
            ruby: "3.2"
            runner: ubuntu-latest
          - target: aarch64-unknown-linux-gnu
            ruby: "3.2"
            runner: ubuntu-latest
          - target: aarch64-apple-darwin
            ruby: "3.2"
            runner: macos-latest
    steps:
      - uses: oxidize-rb/actions/setup-ruby-and-rust@v1
      - run: bundle exec rb-sys-dock --target ${{ matrix.target }} -- rake native gem
```

### ONNX Runtime linking

**Critical:** ONNX Runtime must be statically linked or bundled in the gem for
binary distribution. The `ort` crate supports `ORT_STRATEGY=download` to fetch
the ORT static library at build time. This is the recommended path for gem
distribution — it avoids runtime `libonnxruntime.so` dependency on the user machine.

```toml
# In ext/gte/Cargo.toml, enable ort's download strategy
[features]
default = ["ort/download-binaries"]
```

For Nix dev shell, use the system `onnxruntime` package and `ORT_STRATEGY=system`
(set via flake.nix env vars).

---

## Nix Flake Structure

```nix
# flake.nix — extends nero's pattern with ort strategy env var
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay.url = "github:oxalica/rust-overlay";  # pinned Rust toolchain
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ rust-overlay.overlays.default ];
        };
        rust = pkgs.rust-bin.stable.latest.default.override {
          targets = [ "aarch64-unknown-linux-gnu" "x86_64-unknown-linux-gnu" ];
        };
      in {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            ruby_3_4
            rust
            cargo
            pkg-config
            onnxruntime      # system ORT for dev
            libiconv
            git
          ];
          env = {
            ORT_STRATEGY = "system";
            ORT_LIB_LOCATION = "${pkgs.onnxruntime}";
            # Ensures tokenizers can find its native deps
            RUST_LOG = "ort=warn";
          };
        };
      });
}
```

**Difference from nero's flake:** Add `rust-overlay` for pinned Rust toolchain,
explicit `ORT_STRATEGY=system` env, and cross-compilation targets in the toolchain
override. Nero's flake uses whatever `rustc` nixpkgs ships — fine for local dev
but not for reproducible cross builds.

---

## How nero's Patterns Map to the Embedding Use Case

| nero pattern | Embedding adaptation | Reason |
|-------------|---------------------|--------|
| `OnceCell` global singleton | Remove — per-instance ownership | Multiple models possible; Ruby `@default` is sufficient |
| `LRU` inference cache | Remove | Embedding inputs rarely repeat; memory wasted |
| `Arc<Model>` shared ownership | Remove (single owner per Ruby object) | `#[wrap]` struct GC lifetime sufficient |
| `FxHasher` cache key | Remove (no cache) | — |
| `#[wrap(class = ..., free_immediately)]` | Keep exactly | Same memory model |
| `magnus::init` function with class/method registration | Keep exactly | Same FFI pattern |
| `build.rs` VERSION sync | Keep exactly | Single version source of truth |
| `extconf.rb` with `create_rust_makefile` | Keep exactly | Same build entry point |
| `flake.nix` with `onnxruntime` package | Keep, extend | Add rust-overlay, ORT env vars |
| Ruby facade class wrapping Rust `Model` | Keep | Ergonomic API layer |
| Ruby `config.rb` with defaults | Keep | Model path, preset selection |

---

## Suggested Build Order (Component Dependencies)

```
Phase 1: Scaffold
  ├── flake.nix (dev shell with ort system lib)
  ├── gemspec + Gemfile
  ├── VERSION file
  ├── ext/gte/extconf.rb
  ├── ext/gte/build.rs
  └── ext/gte/Cargo.toml

Phase 2: Core Rust (no Ruby bindings yet)
  ├── error.rs            (GTE error types)
  ├── config.rs           (ModelConfig, ExtractorMode, presets)
  ├── tokenizer.rs        (wrap tokenizers::Tokenizer)
  └── pipeline.rs         (tokenize → tensors → session run → extract)
  [Validate with a Rust integration test against a real model file]

Phase 3: Ruby Bindings
  ├── embedder.rs         (#[wrap] struct, rb_new, rb_embed)
  └── lib.rs              (#[magnus::init], class registration)
  [Validate: bundle exec ruby -e "require 'gte'; p GTE::Embedder.new(...)"]

Phase 4: Ruby API Layer
  ├── lib/gte/config.rb
  ├── lib/gte/embedder.rb (facade)
  └── lib/gte.rb
  [Validate: minimal embed call returns Array<Array<Float>>]

Phase 5: Multi-arch Packaging
  ├── .github/workflows/release.yml (matrix build)
  └── Rakefile (native gem tasks)
  [Validate: gem installs on both aarch64-darwin and x86_64-linux]
```

**Dependency constraint:** Phase 2 must validate against a real ONNX model file
before Phase 3 adds Ruby bindings. It is much easier to debug pipeline errors
from Rust (with `eprintln!`, `#[test]`) than from a Ruby `RuntimeError` with no
stack trace.

---

## Scalability Considerations

| Concern | Dev / single use | Multi-user / high throughput |
|---------|-----------------|------------------------------|
| Session loading | Eager on `Embedder.new` (~200–400ms one-time) | Acceptable; use connection pool pattern in Ruby |
| Batch size | Single text or Vec<String> — ORT handles batching natively | Expose batch size param; larger batches amortize tokenizer overhead |
| Parallelism | GIL: release during `run()` via `magnus::Ruby::get()` is already GIL-safe | Each Embedder instance is independent; Ractors or thread-per-request fine |
| Memory | One ORT Session ≈ model weights in RAM (E5-small ~90MB) | One instance per process; share via Ruby `@default` |

---

## Sources

- `impl/nero/ext/nero/src/lib.rs` — singleton + LRU pattern, magnus wrap
- `impl/nero/ext/nero/Cargo.toml` — rb-sys, magnus, once_cell deps
- `impl/nero/ext/nero/extconf.rb` — create_rust_makefile pattern
- `impl/nero/ext/nero/build.rs` — VERSION sync pattern
- `impl/nero/flake.nix` — Nix dev shell baseline
- `impl/nero/lib/nero.rb` — Ruby facade and `@default` singleton
- `impl/gte-rs/src/embed/pipeline.rs` — composable pre/post processor pipeline
- `impl/gte-rs/src/params/mod.rs` — model-type parameterization via Parameters
- `impl/gte-rs/src/tokenizer/mod.rs` — Tokenized struct (input_ids, attn_masks, optional ids)
- `impl/gte-rs/src/embed/output.rs` — ExtractorMode (Token vs Raw), Precision
- `impl/gte-rs/src/commons/input/tensors.rs` — SessionInputs assembly, optional tensor names
- `impl/gte-rs/Cargo.toml` — ort pin =2.0.0-rc.9, tokenizers 0.21.0, ndarray 0.16.0
