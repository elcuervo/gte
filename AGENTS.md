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

- Minimal benchmark entrypoint: `ruby bench/pure_ruby_compare.rb`.
- It compares GTE against a pure Ruby ONNX Runtime/tokenizers path.
- Environment variables:
  - `GTE_MODEL_DIR`
  - `GTE_CLIP_DIR`
  - `GTE_SIGLIP2_DIR`

## Working Rules

- Prefer small, explicit changes in the Rust inference path.
- Keep tokenization and session behavior aligned with the pure Ruby runtime in `bench/pure_ruby_runtime.rb`.
- Preserve L2 normalization behavior at the Ruby-facing API layer.
- Benchmark any inference-path change with `bench/pure_ruby_compare.rb`.

## Useful Commands

- Always run build, test, and benchmark commands inside `nix develop`.
- `bundle exec rake compile`
- `cargo test --manifest-path ext/gte/Cargo.toml --no-default-features`
- `bundle exec rspec`
- `bundle exec ruby bench/pure_ruby_compare.rb`
