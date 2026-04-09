# frozen_string_literal: true

e5_dir = ENV.fetch("GTE_MODEL_DIR", nil)
siglip2_dir = ENV.fetch("GTE_SIGLIP2_DIR", nil)
clip_dir = ENV.fetch("GTE_CLIP_DIR", nil)
clip_multimodal_dir = ENV.fetch("GTE_CLIP_MULTIMODAL_DIR", nil)

GTE_E5_DIR = e5_dir.freeze
GTE_E5_AVAILABLE = !!(e5_dir && File.exist?(File.join(e5_dir, "tokenizer.json"))).freeze
GTE_EMBEDDING_DIM = ENV.fetch("GTE_EMBEDDING_DIM", "384").to_i

GTE_SIGLIP2_DIR = siglip2_dir.freeze
GTE_SIGLIP2_AVAILABLE = !!(siglip2_dir && File.exist?(File.join(siglip2_dir, "tokenizer.json"))).freeze
GTE_SIGLIP2_EMBEDDING_DIM = ENV.fetch("GTE_SIGLIP2_EMBEDDING_DIM", "768").to_i

GTE_CLIP_DIR = clip_dir.freeze
GTE_CLIP_AVAILABLE = !!(clip_dir && File.exist?(File.join(clip_dir, "tokenizer.json"))).freeze

GTE_CLIP_MULTIMODAL_DIR = clip_multimodal_dir.freeze
GTE_CLIP_MULTIMODAL_AVAILABLE = !!(clip_multimodal_dir && File.exist?(File.join(clip_multimodal_dir, "tokenizer.json"))).freeze

GTE_FIXTURES_AVAILABLE = GTE_E5_AVAILABLE
