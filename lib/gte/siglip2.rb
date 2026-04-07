# frozen_string_literal: true

module GTE
  # Siglip2 text encoder wrapper.
  # NOTE: output_tensor name is LOW CONFIDENCE — requires model inspection.
  # Specs for this class are marked pending until a Siglip2 ONNX fixture is available.
  # Per D-05: pure Ruby wrapper over GTE::Embedder.
  class Siglip2
    def initialize(model_path:, tokenizer_path: nil, config: ModelConfig.siglip2)
      resolved_tokenizer = tokenizer_path || File.join(File.dirname(model_path), "tokenizer.json")
      @embedder = GTE::Embedder.new(
        resolved_tokenizer, model_path,
        config.max_length, config.output_tensor, config.mode.to_s, config.with_type_ids,
        config.with_attention_mask, config.num_threads, config.optimization_level
      )
    end

    # Embed a batch of texts. Returns Array<Array<Float>>.
    def embed(texts)
      @embedder.embed(Array(texts))
    end
  end
end
