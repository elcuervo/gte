# Technology Stack

**Project:** GTE — Ruby gem with Rust cdylib extension for ONNX text embeddings
**Researched:** 2026-04-06
**Overall confidence:** HIGH — anchored to two production reference implementations in `impl/`

---

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

---

## Rationale

### Ruby-Rust FFI: `magnus` over `rutie` or raw `rb-sys`

**Choose `magnus = "0.8"`.**

`rutie` is effectively unmaintained — no modern Ruby 3.x support, community consolidated around `magnus`. Raw `rb-sys` alone is the lower-level C binding layer — `magnus` builds on top to provide safe, ergonomic Rust-idiomatic types. No reason to use raw `rb-sys` for binding code when `magnus` is available.

nero uses `magnus = "0.8"` in production. Highest-confidence data point available.

### ONNX Runtime: `ort` v2 (rc.9 pinned), not `tract`

**Pin `ort = "=2.0.0-rc.9"` exactly.**

Reasons to pin rather than semver range:
1. **ABI stability:** `ort` links against a specific `libonnxruntime` version. A range could break at runtime.
2. **Proven:** gte-rs pins this exact version and runs E5 embedding inference successfully.

`tract` (pure-Rust ONNX alternative) rejected: narrower op coverage, no hardware providers (CoreML, CUDA), slower on large transformer models.

### Tokenizer: `tokenizers = "0.21.0"`

Loads `tokenizer.json` format directly — the standard HuggingFace model repo artifact. Supports BPE (CLIP), WordPiece (E5), SentencePiece-backed (Siglip2), fast truncation, batch encoding with padding-to-batch-longest.

### Nix flake: extend nero with `rust-overlay` + ORT env vars

nero's `flake.nix` is the baseline — `nixpkgs-unstable` + `flake-utils` + `eachDefaultSystem`. Extend with:
1. `oxalica/rust-overlay` — pinned Rust toolchain, enables cross-compilation targets
2. `ORT_STRATEGY = "system"` and `ORT_LIB_LOCATION = "${pkgs.onnxruntime}"` — avoids build-time download

### Cross-compilation: `oxidize-rb/actions/cross-gem`

Wraps rb-sys-dock (Docker + QEMU) — produces platform-specific `.gem` files. nero uses this pattern in `release.yml`. `cargo-vendor: true` critical for cross-compilation inside Docker.

---

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

---

## Version Pins — Final Reference

```toml
# ext/gte/Cargo.toml
[dependencies]
magnus     = "0.8"
rb-sys     = { version = "0.9", features = ["stable-api-compiled-fallback"] }
ort        = "=2.0.0-rc.9"    # exact pin — ABI-sensitive
tokenizers = "0.21.0"
ndarray    = "0.16.0"          # version-locked to ort requirement
half       = "2"
```

```nix
# flake.nix buildInputs
ruby_3_4  rustc  cargo  pkg-config  onnxruntime  libiconv  git
# env vars
ORT_STRATEGY = "system";
ORT_LIB_LOCATION = "${pkgs.onnxruntime}";
```

---

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

---

## Open Questions

1. Does nixpkgs-unstable `onnxruntime` set `ORT_LIB_LOCATION` via pkg-config automatically?
2. Has `ort` shipped a stable v2.0.0 (non-rc) release? Check before migrating.
3. Actual `fastembed` gem architecture — subprocess, FFI, or pure-Ruby ONNX? Affects benchmark design.
4. CoreML execution provider in `ort` v2 — verify builder API for Apple Silicon ANE optimization.

---

## Sources

- `impl/nero/ext/nero/Cargo.toml` — magnus 0.8, rb-sys 0.9 (confirmed)
- `impl/nero/ext/nero/extconf.rb` — `create_rust_makefile` pattern (confirmed)
- `impl/nero/ext/nero/src/lib.rs` — `#[wrap]`, `function!`, `method!`, `#[magnus::init]` (confirmed)
- `impl/nero/.github/workflows/release.yml` — oxidize-rb actions, matrix build (confirmed)
- `impl/gte-rs/Cargo.toml` — ort =2.0.0-rc.9, tokenizers 0.21.0, ndarray 0.16.0 (confirmed)
- `impl/gte-rs/src/tokenizer/mod.rs` — tokenizers API: from_file, encode_batch (confirmed)
- `impl/gte-rs/src/commons/input/tensors.rs` — ort v2 API (confirmed)
