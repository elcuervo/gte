# frozen_string_literal: true

module GTE
  # CLIP text encoder wrapper.
  # Uses CLIP defaults: max_length 77, output "text_embeds", Raw extraction (API-02).
  # Per D-05: pure Ruby wrapper over GTE::Embedder.
  class CLIP
    def initialize(model_path:, tokenizer_path: nil, config: ModelConfig.clip)
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
