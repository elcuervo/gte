# Phase 1: Scaffold - Context

**Gathered:** 2026-04-06
**Status:** Ready for planning

<domain>
## Phase Boundary

Developer can enter a reproducible Nix dev environment, compile the Rust extension, load the gem in Ruby, and have panic-safe error handling in place — before any inference code exists. CI produces native gems for both target architectures.

Requirements in scope: SCAF-01, SCAF-02, SCAF-03, SCAF-04, SCAF-05, SCAF-06

</domain>

<decisions>
## Implementation Decisions

### Nix Flake Design
- **D-01:** Use plain `pkgs.rustc` + `pkgs.cargo` from nixpkgs-unstable — no `rust-overlay`, mirroring nero's approach
- **D-02:** Use `flake-utils.lib.eachDefaultSystem` for multi-system support (aarch64-darwin + x86_64-linux) — same pattern as nero
- **D-03:** Set `ORT_STRATEGY=system` and `ORT_LIB_LOCATION` (pointing to `${pkgs.onnxruntime}`) in the shell's `shellHook` so `bundle exec rake compile` works automatically inside `nix develop`
- **D-04:** `buildInputs` mirrors nero: `ruby_3_4`, `rustc`, `cargo`, `rustfmt`, `onnxruntime`, `pkg-config`, `git`

### Gem & Extension Structure
- **D-05:** Gem is named `gte`; extension lives at `ext/gte/` with `gte.rs` as the library entry — mirrors nero's structure exactly
- **D-06:** `extconf.rb` uses `create_rust_makefile("gte/gte")` — same single-line pattern as nero
- **D-07:** Cargo.toml `crate-type = ["cdylib"]`, dependencies: `magnus = "0.8"`, `rb-sys = { version = "0.9", features = ["stable-api-compiled-fallback"] }`

### Error Handling
- **D-08:** `GTE::Error` Ruby exception class defined — Rust panics and runtime errors are caught and re-raised as `GTE::Error` (never crash the Ruby process)
- **D-09:** Phase 1 Rust init is a skeleton: `#[magnus::init]` that defines the `GTE` module and `GTE::Error` class, with panic hook installed — no inference code yet

### Version Sync (SCAF-05)
- **D-10:** `build.rs` asserts that `Cargo.toml` version matches the `VERSION` file at compile time — same approach used in nero

### CI / Multi-arch Build (SCAF-06)
- **D-11:** GitHub Actions: `oxidize-rb/actions/setup-ruby-and-rust@v1.4.4` + `oxidize-rb/actions/cross-gem@v1` — same actions as nero
- **D-12:** Build matrix: `x86_64-linux` (target: `x86_64-unknown-linux-gnu`) + `arm64-darwin` (target: `aarch64-apple-darwin`) + source gem — mirrors nero's release.yml structure exactly

### Claude's Discretion
- Exact `shellHook` formatting and any additional Nix shell conveniences (e.g., `direnv` hint)
- Gemspec dependency list beyond build tooling (rspec, rake-compiler, rb-sys gem)
- Ruby `require` structure in `lib/gte.rb` (minimal bootstrapping to make `require 'gte'` work)
- How `GTE::Error` is defined on the Ruby side (pure Ruby subclass of `StandardError` or defined in Rust via magnus)
- CI publish target — nero pushes to Gemfury; GTE publish target not decided yet (out of scope for Phase 1 scaffold, Phase 4 handles packaging)

</decisions>

<specifics>
## Specific Ideas

- Mirror nero's structure as closely as possible for Phase 1 — it's a confirmed working reference for the exact same stack (magnus + rb-sys + onnxruntime + Nix)
- The flake should "just work" after `nix develop` — no manual env var exports needed before `rake compile`

</specifics>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Reference scaffold (nero gem)
- `impl/nero/flake.nix` — Working flake: buildInputs, devShell structure, nixpkgs-unstable usage
- `impl/nero/ext/nero/extconf.rb` — `create_rust_makefile` pattern (single line)
- `impl/nero/ext/nero/Cargo.toml` — Confirmed: magnus 0.8, rb-sys 0.9, cdylib, build.rs
- `impl/nero/nero.gemspec` — Gemspec shape: files, require_paths, ruby version constraint
- `impl/nero/Rakefile` — bundler/gem_tasks + RSpec task setup
- `impl/nero/.github/workflows/release.yml` — oxidize-rb actions, cross-gem matrix, platform labels

### Project specs
- `.planning/REQUIREMENTS.md` §Scaffold & Build — SCAF-01 through SCAF-06 acceptance criteria
- `.planning/ROADMAP.md` §Phase 1 — Success criteria (5 items) for phase completion

### Stack decisions
- `CLAUDE.md` (GSD:stack section) — Confirmed versions: magnus 0.8, rb-sys 0.9, ort =2.0.0-rc.9, tokenizers 0.21.0, ndarray 0.16.0; rationale for each choice

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `impl/nero/flake.nix` — Copy and adapt: change package name, add ORT env vars to shellHook
- `impl/nero/ext/nero/extconf.rb` — Copy verbatim, change path string to `"gte/gte"`
- `impl/nero/ext/nero/Cargo.toml` — Copy and strip nero-specific deps (orp, gline-rs, lru, etc.), keep magnus + rb-sys
- `impl/nero/.github/workflows/release.yml` — Copy and adapt: change gem name, remove Gemfury push logic

### Established Patterns
- `create_rust_makefile` is the only line needed in extconf.rb — do not add complexity
- `cdylib` crate type is mandatory for Ruby extensions — not a library
- nero's Rakefile uses `bundler/gem_tasks` + `RSpec::Core::RakeTask` — no custom compile task needed (rake-compiler handles it)

### Integration Points
- The `#[magnus::init]` function is the Ruby extension entry point — it runs when `require 'gte'` is called
- `GTE::Error` must be visible to all subsequent phases; define it in Phase 1 Rust init

</code_context>

<deferred>
## Deferred Ideas

- Gem publish target (RubyGems.org vs Gemfury vs GitHub Packages) — not needed for Phase 1 scaffold; revisit in Phase 4
- `direnv` / `.envrc` integration for non-Nix users — out of scope for v1

</deferred>

---

*Phase: 01-scaffold*
*Context gathered: 2026-04-06*
