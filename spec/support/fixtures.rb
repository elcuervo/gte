# frozen_string_literal: true

# Fixture guard for specs that require real ONNX model files.
# Set GTE_MODEL_PATH and GTE_TOKENIZER_PATH env vars to enable fixture-dependent specs.
# Example:
#   GTE_MODEL_PATH=/path/to/model.onnx GTE_TOKENIZER_PATH=/path/to/tokenizer.json bundle exec rspec

model_path     = ENV.fetch("GTE_MODEL_PATH", nil)
tokenizer_path = ENV.fetch("GTE_TOKENIZER_PATH", ENV.fetch("GTE_MODEL_PATH", nil)&.then { |p| File.join(File.dirname(p), "tokenizer.json") })

GTE_FIXTURES_AVAILABLE = !!(
  model_path && tokenizer_path &&
  File.exist?(model_path) &&
  File.exist?(tokenizer_path)
).freeze

GTE_MODEL_PATH     = model_path.freeze
GTE_TOKENIZER_PATH = tokenizer_path.freeze
GTE_EMBEDDING_DIM  = ENV.fetch("GTE_EMBEDDING_DIM", "768").to_i
