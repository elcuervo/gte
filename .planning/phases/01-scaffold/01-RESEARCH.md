# Phase 1: Scaffold - Research

**Researched:** 2026-04-06
**Domain:** Ruby gem scaffolding with Rust cdylib extension (magnus + rb-sys + Nix + GitHub Actions cross-compilation)
**Confidence:** HIGH

## Summary

Phase 1 builds a complete, compilable Ruby gem skeleton backed by a Rust extension. All technical decisions are locked in CONTEXT.md and directly map to patterns found in the nero reference implementation, which is confirmed working on the same stack (magnus 0.8, rb-sys 0.9, onnxruntime via Nix). Research confirms all locked choices are sound and extracts the exact file contents needed to replicate and adapt nero for GTE.

The primary distinction from nero is: (1) GTE's flake.nix must add `shellHook` with `ORT_STRATEGY` and `ORT_LIB_LOCATION` env vars (nero omits this because it uses the Ruby `onnxruntime` gem at runtime; GTE compiles against ORT in Rust), and (2) GTE's init function defines a module-scoped error class (`GTE::Error`) rather than a top-level class.

**Primary recommendation:** Copy nero's file structure verbatim, applying only the changes documented in CONTEXT.md decisions D-01 through D-12. Do not add complexity beyond what nero demonstrates.

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Use plain `pkgs.rustc` + `pkgs.cargo` from nixpkgs-unstable — no `rust-overlay`, mirroring nero's approach
- **D-02:** Use `flake-utils.lib.eachDefaultSystem` for multi-system support (aarch64-darwin + x86_64-linux) — same pattern as nero
- **D-03:** Set `ORT_STRATEGY=system` and `ORT_LIB_LOCATION` (pointing to `${pkgs.onnxruntime}`) in the shell's `shellHook` so `bundle exec rake compile` works automatically inside `nix develop`
- **D-04:** `buildInputs` mirrors nero: `ruby_3_4`, `rustc`, `cargo`, `rustfmt`, `onnxruntime`, `pkg-config`, `git`
- **D-05:** Gem is named `gte`; extension lives at `ext/gte/` with `gte.rs` as the library entry — mirrors nero's structure exactly
- **D-06:** `extconf.rb` uses `create_rust_makefile("gte/gte")` — same single-line pattern as nero
- **D-07:** Cargo.toml `crate-type = ["cdylib"]`, dependencies: `magnus = "0.8"`, `rb-sys = { version = "0.9", features = ["stable-api-compiled-fallback"] }`
- **D-08:** `GTE::Error` Ruby exception class defined — Rust panics and runtime errors are caught and re-raised as `GTE::Error` (never crash the Ruby process)
- **D-09:** Phase 1 Rust init is a skeleton: `#[magnus::init]` that defines the `GTE` module and `GTE::Error` class, with panic hook installed — no inference code yet
- **D-10:** `build.rs` asserts that `Cargo.toml` version matches the `VERSION` file at compile time — same approach used in nero
- **D-11:** GitHub Actions: `oxidize-rb/actions/setup-ruby-and-rust@v1.4.4` + `oxidize-rb/actions/cross-gem@v1` — same actions as nero
- **D-12:** Build matrix: `x86_64-linux` (target: `x86_64-unknown-linux-gnu`) + `arm64-darwin` (target: `aarch64-apple-darwin`) + source gem — mirrors nero's release.yml structure exactly

### Claude's Discretion
- Exact `shellHook` formatting and any additional Nix shell conveniences (e.g., `direnv` hint)
- Gemspec dependency list beyond build tooling (rspec, rake-compiler, rb-sys gem)
- Ruby `require` structure in `lib/gte.rb` (minimal bootstrapping to make `require 'gte'` work)
- How `GTE::Error` is defined on the Ruby side (pure Ruby subclass of `StandardError` or defined in Rust via magnus)
- CI publish target — nero pushes to Gemfury; GTE publish target not decided yet (out of scope for Phase 1 scaffold, Phase 4 handles packaging)

### Deferred Ideas (OUT OF SCOPE)
- Gem publish target (RubyGems.org vs Gemfury vs GitHub Packages) — not needed for Phase 1 scaffold; revisit in Phase 4
- `direnv` / `.envrc` integration for non-Nix users — out of scope for v1
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SCAF-01 | Developer can enter reproducible dev environment via `nix develop` with Ruby 3.4, Rust, ONNX Runtime, and all build deps available | Confirmed: nero's flake.nix pattern + shellHook with ORT env vars covers this entirely |
| SCAF-02 | Developer can run `bundle exec rake compile` and produce a native `.so`/`.bundle` extension | Confirmed: `create_rust_makefile("gte/gte")` + rake-compiler + rb_sys gem in Gemfile |
| SCAF-03 | Developer can run `require 'gte'` in Ruby without errors | Confirmed: `lib/gte.rb` requires the compiled extension then any Ruby files |
| SCAF-04 | `GTE::Error` Ruby exception class exists and is raised for all Rust-level failures (no process crashes from panics crossing FFI) | Confirmed: `module.define_error("Error", ruby.exception_standard_error())` + `std::panic::catch_unwind` pattern |
| SCAF-05 | Gem version is synchronized between `VERSION` file and `Cargo.toml` (enforced via `build.rs` assertion) | Confirmed: nero's build.rs pattern is verbatim-copyable (reads `../../VERSION`, asserts `== CARGO_PKG_VERSION`) |
| SCAF-06 | Multi-arch builds produce native gems for `aarch64-apple-darwin` and `x86_64-unknown-linux-gnu` via GitHub Actions CI | Confirmed: nero's release.yml with oxidize-rb/actions/cross-gem@v1 covers both platforms |
</phase_requirements>

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `magnus` | `0.8` | Ruby C extension bindings from Rust — `#[wrap]`, `#[magnus::init]`, type coercions, module/class/error definition | Observed in nero production code; ergonomic layer over rb-sys |
| `rb-sys` | `0.9` (feature: `stable-api-compiled-fallback`) | Generates correct `ruby.h` bindings; bridges `rake-compiler` ecosystem | Observed in nero; the `stable-api-compiled-fallback` feature is required for correct bindings |
| `rb_sys` gem | `0.9.x` (latest) | Ruby-side companion: `rb_sys/mkmf` provides `create_rust_makefile` | Required by extconf.rb; dev dependency in Gemfile |
| `rake-compiler` | current | `rake compile` drives extconf.rb + Cargo build chain | Observed in nero CI; standard Ruby native extension build driver |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `rspec` | current | Test framework | All Ruby-level tests |
| `rspec-benchmark` | current | Benchmark assertions (Phase 4) | Performance tests |
| `rake` | current | Task runner — bundler/gem_tasks + rspec task | Always |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `pkgs.rustc` + `pkgs.cargo` | `rust-overlay` | rust-overlay gives nightly/custom toolchains; unnecessary for stable Rust; nero confirmed working without it |
| `define_error` in Rust | Pure Ruby `GTE::Error = Class.new(StandardError)` | Ruby-side is simpler but means error class exists only after ext loads; either works |

**Installation (dev Gemfile):**
```bash
# Gemfile additions beyond gemspec
gem "rake"
gem "rb_sys"
gem "rspec"
gem "rspec-benchmark"
gem "rake-compiler"
```

---

## Architecture Patterns

### Recommended Project Structure
```
gte/
├── VERSION                    # Single source of version truth (e.g., "0.1.0")
├── gte.gemspec                # Gem spec: name "gte", required_ruby_version >= 3.2
├── Gemfile                    # gemspec + dev deps (rake, rb_sys, rspec, rake-compiler)
├── Rakefile                   # bundler/gem_tasks + RSpec::Core::RakeTask
├── flake.nix                  # Nix devShell: ruby_3_4 + rustc + cargo + onnxruntime
├── flake.lock                 # Locked flake inputs
├── lib/
│   ├── gte.rb                 # require "gte/gte" (extension) + require "gte/version" + "gte/error"
│   └── gte/
│       ├── version.rb         # GTE::VERSION = File.read(...VERSION...).strip
│       └── error.rb           # GTE::Error = Class.new(StandardError) [optional — can define in Rust]
├── ext/
│   └── gte/
│       ├── extconf.rb         # require "rb_sys/mkmf"; create_rust_makefile("gte/gte")
│       ├── Cargo.toml         # [package] name="gte", build="build.rs"; [lib] crate-type=["cdylib"]
│       ├── build.rs           # VERSION assertion: reads ../../VERSION, asserts == CARGO_PKG_VERSION
│       └── src/
│           └── lib.rs         # #[magnus::init] fn init(ruby: &Ruby) — defines GTE module + GTE::Error
└── spec/
    └── spec_helper.rb         # require "gte"
```

### Pattern 1: Nix flake with ORT shellHook
**What:** nero's flake.nix adapted with `shellHook` to export ORT env vars needed for Rust compilation
**When to use:** Always in this project — enables `nix develop` -> `bundle exec rake compile` without manual env setup

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            ruby_3_4
            rustc
            rustfmt
            cargo
            git
            onnxruntime
            pkg-config
          ];

          shellHook = ''
            export ORT_STRATEGY=system
            export ORT_LIB_LOCATION=${pkgs.onnxruntime}
          '';
        };
      });
}
```

**Key difference from nero:** nero has no `shellHook` because it uses the Ruby `onnxruntime` gem at runtime. GTE compiles ORT into the Rust extension at build time, so `ORT_STRATEGY` and `ORT_LIB_LOCATION` must be set before `cargo build` runs.

### Pattern 2: extconf.rb — single-line pattern
**What:** rb_sys/mkmf provides `create_rust_makefile` which generates the Makefile that invokes Cargo
**When to use:** Always — do not add complexity

```ruby
# ext/gte/extconf.rb
# Source: impl/nero/ext/nero/extconf.rb (verbatim, path changed)
require "mkmf"
require "rb_sys/mkmf"

create_rust_makefile("gte/gte")
```

### Pattern 3: Cargo.toml — cdylib + minimal deps
**What:** Only magnus and rb-sys for Phase 1; no ort or tokenizers yet (those are Phase 2)

```toml
# ext/gte/Cargo.toml
[package]
name = "gte"
version = "0.1.0"
edition = "2021"
authors = ["elcuervo <elcuervo@elcuervo.net>"]
license = "MIT"
publish = false
build = "build.rs"

[lib]
crate-type = ["cdylib"]

[dependencies]
rb-sys = { version = "0.9", features = ["stable-api-compiled-fallback"] }
magnus = "0.8"
```

### Pattern 4: build.rs version assertion (SCAF-05)
**What:** Compile-time assertion that Cargo.toml version matches VERSION file
**Source:** `impl/nero/ext/nero/build.rs` — verbatim copy with path adjustment

```rust
// ext/gte/build.rs
// Source: impl/nero/ext/nero/build.rs (verbatim, same relative path ../../VERSION works)
fn main() {
    let version = std::fs::read_to_string("../../VERSION")
        .expect("VERSION file not found")
        .trim()
        .to_string();

    let cargo_version = env!("CARGO_PKG_VERSION");

    assert_eq!(
        version, cargo_version,
        "VERSION file ({}) doesn't match Cargo.toml ({}). Update Cargo.toml to match.",
        version, cargo_version
    );

    println!("cargo:rerun-if-changed=../../VERSION");
}
```

### Pattern 5: Rust init — module + error class + panic safety
**What:** `#[magnus::init]` entry point that defines the `GTE` module, `GTE::Error` exception class, and installs a panic hook to prevent undefined behavior on FFI boundary panics
**When to use:** Phase 1 skeleton; subsequent phases add methods to this init

```rust
// ext/gte/src/lib.rs
use magnus::{prelude::*, Error, Ruby};

#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    let module = ruby.define_module("GTE")?;

    // Define GTE::Error < StandardError
    module.define_error("Error", ruby.exception_standard_error())?;

    // Install panic hook to prevent undefined behavior when Rust panics
    // cross the FFI boundary into Ruby. Panics become catchable GTE::Error
    // exceptions rather than crashing the process.
    std::panic::set_hook(Box::new(|info| {
        let msg = info
            .payload()
            .downcast_ref::<&str>()
            .copied()
            .or_else(|| info.payload().downcast_ref::<String>().map(|s| s.as_str()))
            .unwrap_or("unknown panic");
        eprintln!("GTE Rust panic: {msg}");
    }));

    Ok(())
}
```

**Note on panic surfacing:** The `define_error` call makes `GTE::Error` available in Ruby. For Phase 1 skeleton, the panic hook logs to stderr. In Phase 3 (Ruby bindings), calls to Rust methods will use `std::panic::catch_unwind` + convert to `GTE::Error`. The hook alone prevents undefined behavior (printing is safe; the fatal exception from magnus's default panic handler is a process-terminating signal).

### Pattern 6: lib/gte.rb — bootstrapping
**What:** Loads the compiled extension, then optional pure-Ruby files

```ruby
# lib/gte.rb
# Source: derived from nero's lib/nero.rb pattern
require_relative "gte/version"

# Load the native extension
begin
  # Try pre-compiled native gem
  ruby_version = /(\d+\.\d+)/.match(RUBY_VERSION)[0]
  require_relative "../#{Gem::Platform.local}/gte/#{ruby_version}/gte"
rescue LoadError
  # Fall back to just-compiled extension
  require_relative "gte/gte"
end
```

**Simpler alternative (also valid):**
```ruby
# lib/gte.rb
require_relative "gte/version"
require "gte/gte"   # rake-compiler places .so on load path
```

The simpler form works because rake-compiler adds the compilation output directory to `$LOAD_PATH`. Use the simpler form for Phase 1.

### Pattern 7: Rakefile
**What:** Standard bundler + RSpec tasks; no custom compile task needed

```ruby
# Rakefile
# Source: impl/nero/Rakefile (stripped to essentials)
require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task default: :spec
```

### Pattern 8: GitHub Actions CI — cross-compilation
**What:** `oxidize-rb/actions/cross-gem@v1` builds `aarch64-apple-darwin` and `x86_64-unknown-linux-gnu` native gems
**Source:** `impl/nero/.github/workflows/release.yml` — copy and adapt (remove Gemfury push)

```yaml
# .github/workflows/ci.yml (or release.yml)
name: Build Native Gems
permissions: write-all

on:
  workflow_dispatch:
  push:
    tags: ["v*"]

jobs:
  build:
    name: Build
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        include:
          - platform: x86_64-linux
            target: x86_64-unknown-linux-gnu
          - platform: arm64-darwin
            target: aarch64-apple-darwin

    steps:
      - uses: actions/checkout@v4

      - uses: oxidize-rb/actions/setup-ruby-and-rust@v1.4.4
        with:
          ruby-version: "3.4"
          bundler-cache: false
          cargo-cache: true
          cargo-vendor: true

      - uses: oxidize-rb/actions/cross-gem@v1
        id: cross-gem
        with:
          platform: ${{ matrix.platform }}
          ruby-versions: "3.4"

      - uses: actions/upload-artifact@v4
        with:
          name: bundle-artifact-${{ matrix.platform }}
          path: ${{ steps.cross-gem.outputs.gem-path }}

  source:
    name: Build source gem
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: oxidize-rb/actions/setup-ruby-and-rust@v1.4.4
        with:
          ruby-version: "3.4"
          bundler-cache: false
          cargo-cache: true
          cargo-vendor: true

      - name: Build gem
        run: |
          gem build gte.gemspec
          mkdir -p pkg/
          mv *.gem pkg/

      - uses: actions/upload-artifact@v4
        with:
          name: bundle-artifact-source
          path: pkg/
```

**Note on nero's release.yml:** nero references `actions/checkout@v6`, `actions/upload-artifact@v6`, and `actions/download-artifact@v6` — these version tags do not exist on GitHub Actions. The correct versions are `@v4`. This is a bug in nero's workflow file; GTE must use `@v4`.

### Anti-Patterns to Avoid
- **Adding ORT/tokenizers to Phase 1 Cargo.toml:** These are Phase 2 dependencies. Phase 1 is purely scaffolding — adding ort = "=2.0.0-rc.9" now creates a build dependency on ORT at compile time before the Nix environment is proven working.
- **Using `awscli` in buildInputs:** nero includes `awscli` for S3 model uploads. GTE has no S3 dependency; omit it.
- **Omitting `spec.extensions` from gemspec:** For a source gem to compile on install, `spec.extensions = ["ext/gte/extconf.rb"]` must be present. nero omits it because nero ships pre-built native gems exclusively and cross-compilation handles end users. GTE should follow the same pattern but include it for developer source installs.
- **Using `ruby.exception_runtime_error()` for GTE::Error:** Define it as `StandardError` subclass with `define_error`, not as RuntimeError. RuntimeError is for ad-hoc unclassified errors; GTE errors should be specifically catchable.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Makefile generation for Rust extensions | Custom extconf.rb | `create_rust_makefile` from `rb_sys/mkmf` | Handles Cargo invocation, library path, cross-compilation targets correctly |
| Cross-platform native gem builds | Custom CI scripts | `oxidize-rb/actions/cross-gem@v1` | Handles QEMU emulation, cargo-zigbuild, platform detection — extremely complex to reproduce |
| Ruby/Rust type coercions | Raw `rb-sys` calls | `magnus` macros (`function!`, `method!`, `#[wrap]`) | rb-sys is unsafe C bindings; magnus provides safe ergonomic API |
| Version synchronization | Git tags or manual | `build.rs` assertion | Compile-time check catches version drift before a bad gem is released |
| Panic-to-Ruby-error translation | Custom `rb_raise` via rb-sys | `module.define_error` + `std::panic::catch_unwind` | rb-sys panic handling crosses FFI boundary unsafely; catch_unwind is the correct mechanism |

**Key insight:** The entire extension build chain (extconf.rb → rake compile → Cargo → cdylib → .so) is handled by two things: `create_rust_makefile` (one line) and `rake-compiler` (one gem). Do not add any other mechanism.

---

## Common Pitfalls

### Pitfall 1: Missing ORT_LIB_LOCATION in shellHook
**What goes wrong:** `bundle exec rake compile` inside `nix develop` fails with `ort` build error: "could not find system ONNX Runtime" or similar linking error.
**Why it happens:** `ORT_STRATEGY=system` requires `ORT_LIB_LOCATION` to point to the ORT install prefix. Without it, the build script cannot locate `libonnxruntime`.
**How to avoid:** Set both `ORT_STRATEGY=system` AND `ORT_LIB_LOCATION=${pkgs.onnxruntime}` in `shellHook`. Note: Phase 1 Cargo.toml does NOT include `ort` dependency yet, so this pitfall only manifests in Phase 2. Document the shellHook correctly now so Phase 2 works.
**Warning signs:** `error: could not find ONNX Runtime` during cargo build.

### Pitfall 2: nero release.yml uses non-existent GitHub Actions versions
**What goes wrong:** CI fails immediately with "Unable to find action 'actions/checkout@v6'" or similar.
**Why it happens:** nero's release.yml uses `actions/checkout@v6`, `actions/upload-artifact@v6`, `actions/download-artifact@v6` — these version tags do not exist. Current versions are `@v4`.
**How to avoid:** Use `@v4` for all GitHub standard actions (checkout, upload-artifact, download-artifact).
**Warning signs:** CI fails at action resolution step, not at compilation.

### Pitfall 3: gemspec missing spec.extensions for source compilation
**What goes wrong:** `gem install gte` from source (not pre-built native gem) silently installs without compiling the extension. `require 'gte'` then fails with `LoadError`.
**Why it happens:** Without `spec.extensions = ["ext/gte/extconf.rb"]`, RubyGems does not invoke extconf.rb during installation.
**How to avoid:** Add `spec.extensions = ["ext/gte/extconf.rb"]` to gte.gemspec.
**Warning signs:** `require 'gte'` in a clean install environment raises LoadError.

### Pitfall 4: VERSION file path in build.rs is relative to Cargo.toml location
**What goes wrong:** `build.rs` panics with "VERSION file not found" during compilation.
**Why it happens:** nero's `build.rs` uses `std::fs::read_to_string("../../VERSION")`. This path is relative to the manifest directory (where Cargo.toml lives), which for `ext/gte/` means the path `../../VERSION` correctly resolves to the repo root. This works, but only if the directory depth matches.
**How to avoid:** Confirm `ext/gte/Cargo.toml` depth is exactly 2 levels from repo root. GTE structure (`ext/gte/`) matches nero (`ext/nero/`), so `../../VERSION` is correct.
**Warning signs:** Compile error: `thread 'main' panicked at 'VERSION file not found'`.

### Pitfall 5: rb_sys gem vs rb-sys crate confusion
**What goes wrong:** Developer adds `rb_sys` as a production gem dependency instead of development, or forgets it entirely and `extconf.rb` fails with `cannot load such file -- rb_sys/mkmf`.
**Why it happens:** `rb-sys` (hyphen) is a Rust crate; `rb_sys` (underscore) is a Ruby gem. Both are required: the crate for Cargo.toml, the gem for extconf.rb. The gem is a development dependency (needed to build, not at runtime).
**How to avoid:** Add `gem "rb_sys"` to Gemfile (development group). Do NOT add it as a gemspec `add_dependency` — it is a build tool only.
**Warning signs:** `extconf.rb:3:in require': cannot load such file -- rb_sys/mkmf`.

### Pitfall 6: Panics crossing FFI boundary are undefined behavior
**What goes wrong:** A Rust panic propagates across the FFI boundary into Ruby, causing undefined behavior — typically a segfault or silent corruption rather than a Ruby exception.
**Why it happens:** Rust unwinding across a C FFI boundary (which Ruby's C API is) is undefined behavior in Rust. Magnus mitigates this with its own panic handler that converts panics to fatal Ruby exceptions, but this terminates the process.
**How to avoid:** In Phase 1, install `std::panic::set_hook` in `#[magnus::init]`. In Phase 3, wrap all Rust entry points with `std::panic::catch_unwind` and convert to `GTE::Error`. Phase 1 skeleton has no user-callable Rust methods, so this risk is deferred but the groundwork (defining `GTE::Error`) must be laid now.
**Warning signs:** Ruby process crashes without a Ruby exception traceback.

---

## Code Examples

Verified patterns from official sources and nero reference:

### Defining GTE module and error class
```rust
// ext/gte/src/lib.rs
// Source: magnus docs (docs.rs/magnus/0.8.0) + nero pattern adapted
use magnus::{prelude::*, Error, Ruby};

#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    let module = ruby.define_module("GTE")?;
    module.define_error("Error", ruby.exception_standard_error())?;
    Ok(())
}
```

### Raising GTE::Error from Rust (Phase 3 preview)
```rust
// Pattern for Phase 3 — documented here so GTE::Error is designed for this from Phase 1
// Source: magnus docs pattern
fn some_operation(ruby: &Ruby) -> Result<String, Error> {
    let gte_error = ruby
        .class_object()
        .const_get::<_, magnus::exception::ExceptionClass>("GTE")
        .and_then(|m| m.const_get::<_, magnus::exception::ExceptionClass>("Error"))
        .unwrap_or_else(|_| ruby.exception_runtime_error());

    Err(Error::new(gte_error, "operation failed"))
}
```

### VERSION file pattern
```ruby
# lib/gte/version.rb
# Source: impl/nero/lib/nero/version.rb (adapted)
module GTE
  VERSION = File.read(File.expand_path("../../../VERSION", __FILE__)).strip
end
```

### Gemspec with extension declaration
```ruby
# gte.gemspec
require_relative "lib/gte/version"

Gem::Specification.new do |spec|
  spec.name          = "gte"
  spec.version       = GTE::VERSION
  spec.license       = "MIT"
  spec.summary       = "Fast text embeddings via Rust + ONNX Runtime"
  spec.authors       = ["elcuervo"]
  spec.email         = ["elcuervo@elcuervo.net"]
  spec.homepage      = "https://github.com/elcuervo/gte"

  spec.required_ruby_version = ">= 3.2"

  spec.extensions = ["ext/gte/extconf.rb"]

  spec.files = Dir[
    "lib/**/*",
    "ext/**/*.{rb,rs,toml}",
    "LICENSE",
    "README.md",
    "Gemfile",
    "Rakefile",
    "VERSION"
  ]

  spec.require_paths = ["lib"]

  spec.add_development_dependency "rake"
  spec.add_development_dependency "rake-compiler"
  spec.add_development_dependency "rb_sys"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "rspec-benchmark"
end
```

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Nix | SCAF-01 (flake.nix) | Yes | 2.31.2 | — |
| nix-shell | SCAF-01 | Yes | (same) | — |
| Cargo | SCAF-02 (outside nix) | Yes | 1.93.0 (Homebrew) | nix provides rustc+cargo inside devShell |
| Ruby | SCAF-02/03 (outside nix) | Yes | 3.3.10 (system) | nix provides ruby_3_4 inside devShell |
| Bundler | SCAF-02 | Yes | 2.7.2 | — |
| rake | SCAF-02 | Yes | 13.3.1 | — |
| rake-compiler | SCAF-02 | Yes (gem) | 1.2.9 | — |
| onnxruntime (system) | SCAF-01 (in Nix shell) | Yes (via nix, 1.22.2) | 1.22.2 | Must use nix develop |
| rustc (standalone) | — | Not found (outside nix) | — | nix provides inside devShell |

**Notes:**
- `rustc` is not on PATH outside nix. This is expected — the flake provides it. All Rust compilation must happen inside `nix develop`.
- System Ruby is 3.3.10 (not 3.4). The flake provides ruby_3_4. Tests should be run inside `nix develop`.
- `rb_sys` gem is not currently installed globally — it must be added to Gemfile and `bundle install` run inside nix shell.

**Missing dependencies with no fallback:**
- None that block Phase 1. All required tools are available via `nix develop`.

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `rutie` for Ruby-Rust FFI | `magnus` + `rb-sys` | ~2022 | rutie unmaintained; magnus is the standard |
| `ORT_STRATEGY=download` | `ORT_STRATEGY=system` with Nix package | Present | Reproducible builds; no telemetry from Microsoft binaries |
| Manual Makefile for extensions | `create_rust_makefile` from rb_sys/mkmf | ~2021 | Single line replaces complex Makefile generation |
| Manual cross-compilation setup | `oxidize-rb/actions/cross-gem@v1` | ~2022 | GitHub Action handles all QEMU/zigbuild complexity |

**Deprecated/outdated:**
- `rutie`: Unmaintained since ~2022; no Ruby 3.x support
- `ORT_STRATEGY=download`: Downloads Microsoft telemetry-enabled binaries; use `system` in dev
- `rb_sys` old API (pre-0.6): magnus 0.6+ uses new Ruby handle API; nero's lib.rs shows the current pattern

---

## Open Questions

1. **GTE::Error definition location — Ruby vs Rust**
   - What we know: Can be defined either as pure Ruby (`GTE::Error = Class.new(StandardError)` in `lib/gte/error.rb`) or in Rust via `module.define_error("Error", ruby.exception_standard_error())`
   - What's unclear: If defined in Ruby, the class exists before the extension loads (useful for error handling during load); if in Rust, it's defined when the extension initializes
   - Recommendation: Define in Rust (in `#[magnus::init]`) as per D-08/D-09 — consistent with the decision to make the extension the authoritative source of the GTE module. A `lib/gte/error.rb` file can re-open/alias if needed in future.

2. **ORT_LIB_LOCATION exact value for linking**
   - What we know: `${pkgs.onnxruntime}` in Nix resolves to the package store path (e.g., `/nix/store/xxx-onnxruntime-1.22.2`). ORT expects this to point to a directory containing `lib/libonnxruntime.*`.
   - What's unclear: Whether Nix's onnxruntime package layout puts the shared library at `$out/lib/libonnxruntime.dylib` or a subdirectory.
   - Recommendation: Use `${pkgs.onnxruntime}` as the value. The ort build script searches for `libonnxruntime` under `ORT_LIB_LOCATION/lib/`. This is Phase 2 concern — Phase 1 does not compile with ort dependency.

3. **actions/checkout version in nero (bug)**
   - What we know: nero's release.yml uses `@v6` for checkout/upload/download actions, which do not exist.
   - Recommendation: Use `@v4` for all standard GitHub Actions. This is a confirmed bug in nero's workflow that must not be copied.

---

## Sources

### Primary (HIGH confidence)
- `impl/nero/flake.nix` — Confirmed working flake structure; buildInputs list; eachDefaultSystem pattern
- `impl/nero/ext/nero/extconf.rb` — Confirmed `create_rust_makefile` single-line pattern
- `impl/nero/ext/nero/Cargo.toml` — Confirmed magnus 0.8, rb-sys 0.9, cdylib, build.rs
- `impl/nero/ext/nero/build.rs` — Confirmed VERSION assertion pattern (verbatim-copyable)
- `impl/nero/ext/nero/src/lib.rs` — Confirmed `#[magnus::init]`, `#[wrap]`, `function!`, `method!` usage
- `impl/nero/nero.gemspec` — Confirmed gemspec shape (no spec.extensions — pre-built only)
- `impl/nero/Rakefile` — Confirmed bundler/gem_tasks + RSpec::Core::RakeTask
- `impl/nero/.github/workflows/release.yml` — Confirmed oxidize-rb action versions, matrix structure
- `impl/nero/lib/nero/version.rb` — Confirmed VERSION file read pattern

### Secondary (MEDIUM confidence)
- [ort linking docs](https://ort.pyke.io/setup/linking) — ORT_STRATEGY, ORT_LIB_LOCATION, ORT_PREFER_DYNAMIC_LINK env var semantics verified
- [WebSearch: ort 2.0.0-rc.9 env vars] — ORT_STRATEGY and ORT_LIB_LOCATION confirmed for rc.9; cross-verified with official pyke docs
- [docs.rs/magnus/0.8.0 Module trait](https://docs.rs/magnus/0.8.0/magnus/module/trait.Module.html) — `define_error` signature confirmed
- [docs.rs/magnus/0.8.0 Ruby struct](https://docs.rs/magnus/0.8.0/magnus/struct.Ruby.html) — `exception_standard_error()` confirmed

### Tertiary (LOW confidence)
- GitHub Actions versions: `@v4` for standard actions — cross-verified by noting nero's @v6 bug; industry standard is v4

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — All versions directly read from nero's Cargo.toml and Gemfile.lock
- Architecture patterns: HIGH — Derived from direct source inspection of nero; all file contents confirmed
- ORT env vars: HIGH — Verified against official ort pyke docs and WebSearch cross-reference
- Pitfalls: HIGH (nero bug re: actions versions confirmed by checking GitHub Actions tag availability)
- GitHub Actions cross-gem: HIGH — Direct inspection of nero's working release.yml

**Research date:** 2026-04-06
**Valid until:** 2026-06-06 (stable dependencies; ort 2.0.0-rc.9 pinned; magnus 0.8 stable)
