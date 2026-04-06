<!-- GSD:project-start source:PROJECT.md -->
## Project

**GTE — Ruby Gem for Fast Text Embeddings (Rust-backed)**

A Ruby gem powered by a Rust extension that generates text embeddings using ONNX Runtime, targeting the fastest possible inference for E5, Siglip2, and CLIP models. Inspired by `gte-rs` for the embedding pipeline and `nero` for the Ruby-Rust-Nix gem scaffolding. The first milestone validates that text embedding generation is faster than the `fastembed` gem for compatible models.

**Core Value:** Generate text embeddings faster than `fastembed` for E5, Siglip2, and CLIP — with a minimal, ergonomic Ruby API backed by Rust.

### Constraints

- **Tech stack**: Ruby >= 3.2, Rust edition 2021, ONNX Runtime via `ort` crate
- **Build**: flake.nix for reproducible dev environments, multi-arch (aarch64-darwin + x86_64-linux)
- **Scope**: Minimal — validate embedding speed before expanding features
- **Compatibility**: Models provided as local ONNX files + tokenizer JSON for v1
<!-- GSD:project-end -->

<!-- GSD:stack-start source:research/STACK.md -->
## Technology Stack

## Recommended Stack
### Ruby-Rust FFI Layer
| Technology | Version | Purpose | Source |
|------------|---------|---------|--------|
| `magnus` | `0.8` | Ruby C extension bindings from Rust — `#[wrap]`, `#[magnus::init]`, type coercions | nero `ext/nero/Cargo.toml` |
| `rb-sys` | `0.9` (feature: `stable-api-compiled-fallback`) | Generates correct `ruby.h` bindings for the Cargo build; bridges `rake-compiler` ecosystem | nero `ext/nero/Cargo.toml` |
### ONNX Runtime
| Technology | Version | Purpose | Source |
|------------|---------|---------|--------|
| `ort` | `=2.0.0-rc.9` (pinned) | ONNX Runtime Rust bindings — session creation, inference, tensor I/O | gte-rs `Cargo.toml` |
### Tokenization
| Technology | Version | Purpose | Source |
|------------|---------|---------|--------|
| `tokenizers` | `0.21.0` | HuggingFace tokenizers — BPE/WordPiece from `tokenizer.json`, batched encoding, padding, truncation | gte-rs `Cargo.toml` |
### Tensor Operations
| Technology | Version | Purpose | Source |
|------------|---------|---------|--------|
| `ndarray` | `0.16.0` | N-dimensional array type for tensor construction and slicing | gte-rs `Cargo.toml` |
| `half` | `2` | F16 ↔ F32 conversion for models with FP16 output tensors | gte-rs `Cargo.toml` |
### Build Toolchain
| Technology | Version | Purpose | Source |
|------------|---------|---------|--------|
| `rb_sys/mkmf` | (via `rb-sys` gem) | `create_rust_makefile("gte/gte")` — single-line extconf.rb | nero `ext/nero/extconf.rb` |
| `rake-compiler` | current | `rake compile` invokes extconf.rb, drives Cargo | nero `tests.yml` |
| `oxidize-rb/actions/cross-gem` | v1 | GitHub Actions cross-compilation — produces `--platform` native gems | nero `release.yml` |
| `oxidize-rb/actions/setup-ruby-and-rust` | v1.4.4 | CI action: installs Ruby + Rust toolchain together | nero `release.yml` |
| Nix `onnxruntime` package | nixpkgs-unstable | Dev-shell system ORT library; `ORT_STRATEGY=system` | nero `flake.nix` |
### Ruby Layer
| Technology | Version | Purpose |
|------------|---------|---------|
| Ruby | `>= 3.2` | Required minimum |
| `rake` | current | `rake compile`, `rake native gem` tasks |
| `rspec` | current | Test framework |
| `rspec-benchmark` | current | Benchmark assertions |
## Rationale
### Ruby-Rust FFI: `magnus` over `rutie` or raw `rb-sys`
### ONNX Runtime: `ort` v2 (rc.9 pinned), not `tract`
### Tokenizer: `tokenizers = "0.21.0"`
### Nix flake: extend nero with `rust-overlay` + ORT env vars
### Cross-compilation: `oxidize-rb/actions/cross-gem`
## What NOT to Use
| Tool | Reason |
|------|--------|
| `rutie` | Unmaintained since ~2022, no modern Ruby 3.x support |
| Raw `rb-sys` for binding code | `magnus` is the ergonomic layer — use `magnus` for bindings |
| `tract` | Narrower op coverage, no hardware providers, slower on transformer models |
| `ORT_STRATEGY=download` in dev shell | Use `ORT_STRATEGY=system` in Nix — reproducible |
| Ruby `onnxruntime` gem | Not needed — Rust extension calls ORT directly |
| Ruby `tokenizers` gem | Not needed — tokenization is in Rust |
| `orp` crate | Pipeline abstraction adds no value for a single-method cdylib |
| Global `OnceCell` singleton | GTE supports multiple models per process; per-instance is correct |
## Version Pins — Final Reference
# ext/gte/Cargo.toml
# flake.nix buildInputs
# env vars
## Confidence Levels
| Area | Confidence | Reason |
|------|------------|--------|
| `magnus` + `rb-sys` choice | HIGH | Directly observed in nero production code |
| `extconf.rb` + `rake-compiler` pattern | HIGH | Directly observed in nero CI |
| `ort = "=2.0.0-rc.9"` pin | HIGH | gte-rs pins this exact version; API confirmed in source |
| `tokenizers = "0.21.0"` | HIGH | gte-rs pins this; encode_batch API confirmed |
| `ndarray = "0.16.0"` | HIGH | gte-rs pins this; slice/push_row API confirmed |
| `oxidize-rb/actions/cross-gem` | HIGH | Used in nero's release.yml |
| Nix flake base pattern | HIGH | nero's flake.nix confirmed as working baseline |
| `rust-overlay` addition for Nix | MEDIUM | Standard pattern; not in nero's flake |
| `ORT_STRATEGY=system` env in Nix | MEDIUM | Correct mechanism; nero's flake may use pkg-config |
| `fastembed` gem internals | MEDIUM | Training knowledge — verify before benchmark claims |
## Open Questions
## Sources
- `impl/nero/ext/nero/Cargo.toml` — magnus 0.8, rb-sys 0.9 (confirmed)
- `impl/nero/ext/nero/extconf.rb` — `create_rust_makefile` pattern (confirmed)
- `impl/nero/ext/nero/src/lib.rs` — `#[wrap]`, `function!`, `method!`, `#[magnus::init]` (confirmed)
- `impl/nero/.github/workflows/release.yml` — oxidize-rb actions, matrix build (confirmed)
- `impl/gte-rs/Cargo.toml` — ort =2.0.0-rc.9, tokenizers 0.21.0, ndarray 0.16.0 (confirmed)
- `impl/gte-rs/src/tokenizer/mod.rs` — tokenizers API: from_file, encode_batch (confirmed)
- `impl/gte-rs/src/commons/input/tensors.rs` — ort v2 API (confirmed)
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd:quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd:debug` for investigation and bug fixing
- `/gsd:execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd:profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
