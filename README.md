# gte

`gte` is a Ruby gem with a Rust extension for fast text embeddings with ONNX Runtime.

## Scope

- Text embeddings only.
- CLIP and Siglip2 are supported as text-encoder integrations.
- Multimodal/image inputs are intentionally unsupported.

## Quick Start

```ruby
require "gte"

model = GTE.new(ENV.fetch("GTE_MODEL_DIR"))
vector = model["query: hello world"]
```

## Model Directory

A model directory must include `tokenizer.json` and one ONNX model, resolved in this order:

1. `onnx/text_model.onnx`
2. `text_model.onnx`
3. `onnx/model.onnx`
4. `model.onnx`

## Development

Run commands inside `nix develop`.

```bash
bundle exec rake compile
cargo test --manifest-path ext/gte/Cargo.toml --no-default-features
bundle exec rspec
```

## Benchmark

The repo includes one minimal comparison benchmark against a pure Ruby ONNX Runtime path:

```bash
bundle exec rake bench:pure_compare
```
