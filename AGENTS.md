# AGENTS.md

This repository is a Ruby gem with a Rust extension for text embeddings.

## Scope

- Keep the product focused on text embeddings.
- Treat CLIP and Siglip2 as text-encoder integrations only.
- Do not add multimodal/image input support unless explicitly requested.

## Architecture

- Ruby entrypoint: `lib/gte.rb`.
- Ruby FFI boundary: `ext/gte/src/ruby_embedder.rs`.
- Core inference path: `ext/gte/src/embedder.rs`, `ext/gte/src/session.rs`, `ext/gte/src/tokenizer.rs`, `ext/gte/src/postprocess.rs`.

## Model Layout

- Runtime expects a model directory containing `tokenizer.json`.
- ONNX resolution is text-only and prefers:
  1. `onnx/text_model.onnx`
  2. `text_model.onnx`
  3. `onnx/model.onnx`
  4. `model.onnx`
- Multimodal graphs with inputs like `pixel_values` are unsupported by design.

## Benchmark

- Comparison benchmark: `ruby bench/pure_ruby_compare.rb`.
- Puma-like benchmark: `ruby bench/puma_compare.rb`.
- Run ledger and regression checks: `ruby bench/runs_ledger.rb`.
- Primary goal metric: response-time p95 (median of 3 runs) at concurrency `16`.
- Environment variables:
  - `GTE_MODEL_DIR`
  - `GTE_CLIP_DIR`
  - `GTE_SIGLIP2_DIR`
  - Optional Puma tuning target: `GTE_PUMA_CONCURRENCY` (default `16`).

## Working Rules

- Prefer small, explicit changes in the Rust inference path.
- Keep tokenization and session behavior aligned with the pure Ruby runtime in `bench/pure_ruby_runtime.rb`.
- Preserve L2 normalization behavior at the Ruby-facing API layer.
- Benchmark any inference-path change with `bench/puma_compare.rb` and record results in `RUNS.md`.
- After every refactor touching `session.rs`, `embedder.rs`, `postprocess.rs`, or `tokenizer.rs`, run `make bench-record` and verify the regression check passes before committing.

## Execution Provider Policy

- Default execution provider is **CPU fallback** via ONNX Runtime default provider (`GTE_EXECUTION_PROVIDERS=cpu` or unset).
- Do NOT add CoreML as a default provider. CoreML adds significant overhead for text embedding models on Apple Silicon (observed 3–6× latency increase for CLIP, 2× for Siglip2) despite appearing to be a sensible acceleration backend.
- Users who want explicit provider registration can opt in via `GTE_EXECUTION_PROVIDERS=xnnpack` or `GTE_EXECUTION_PROVIDERS=xnnpack,coreml`.

## Useful Commands

- Always run build, test, and benchmark commands inside `nix develop`.
- A `Makefile` groups common dev tasks; prefer `make <target>` over raw commands.
- `make setup` — install Ruby dependencies
- `make compile` — compile the Rust extension
- `make test` — run Rust and Ruby tests
- `make lint` — run clippy + rubocop (catches dead code, unused imports, style issues)
- `make bench` — run Puma-like benchmark
- `make bench-record` — record benchmark results
- `make ci` — full lint + test pipeline
- `make clean` — remove build artifacts
- `bundle exec ruby bench/pure_ruby_compare.rb`
- `bundle exec ruby bench/runs_ledger.rb append --latest`
