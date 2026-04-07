# frozen_string_literal: true

# Fixture guard for specs that require real ONNX model files.
# Set GTE_MODEL_PATH and GTE_TOKENIZER_PATH env vars to enable E5 fixture-dependent specs.
# Set GTE_SIGLIP2_MODEL_PATH for Siglip2 fixture-dependent specs.
# Example:
#   GTE_MODEL_PATH=/path/to/model.onnx bundle exec rspec

model_path     = ENV.fetch("GTE_MODEL_PATH", nil)
tokenizer_path = ENV.fetch("GTE_TOKENIZER_PATH", model_path&.then { |p| File.join(File.dirname(p), "tokenizer.json") })

GTE_FIXTURES_AVAILABLE = !!(
  model_path && tokenizer_path &&
  File.exist?(model_path) &&
  File.exist?(tokenizer_path)
).freeze

GTE_MODEL_PATH     = model_path.freeze
GTE_TOKENIZER_PATH = tokenizer_path.freeze
GTE_EMBEDDING_DIM  = ENV.fetch("GTE_EMBEDDING_DIM", "384").to_i

# Siglip2 fixtures
siglip2_model_path     = ENV.fetch("GTE_SIGLIP2_MODEL_PATH", nil)
siglip2_tokenizer_path = ENV.fetch("GTE_SIGLIP2_TOKENIZER_PATH", siglip2_model_path&.then { |p| File.join(File.dirname(p), "tokenizer.json") })

GTE_SIGLIP2_FIXTURES_AVAILABLE = !!(
  siglip2_model_path && siglip2_tokenizer_path &&
  File.exist?(siglip2_model_path) &&
  File.exist?(siglip2_tokenizer_path)
).freeze

GTE_SIGLIP2_MODEL_PATH     = siglip2_model_path.freeze
GTE_SIGLIP2_TOKENIZER_PATH = siglip2_tokenizer_path.freeze
GTE_SIGLIP2_EMBEDDING_DIM  = ENV.fetch("GTE_SIGLIP2_EMBEDDING_DIM", "768").to_i

# CLIP fixtures
clip_model_path     = ENV.fetch("GTE_CLIP_MODEL_PATH", nil)
clip_tokenizer_path = ENV.fetch("GTE_CLIP_TOKENIZER_PATH", clip_model_path&.then { |p| File.join(File.dirname(p), "tokenizer.json") })

GTE_CLIP_FIXTURES_AVAILABLE = !!(
  clip_model_path && clip_tokenizer_path &&
  File.exist?(clip_model_path) &&
  File.exist?(clip_tokenizer_path)
).freeze

GTE_CLIP_MODEL_PATH     = clip_model_path.freeze
GTE_CLIP_TOKENIZER_PATH = clip_tokenizer_path.freeze
