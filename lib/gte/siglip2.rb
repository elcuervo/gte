# frozen_string_literal: true

module GTE
  # Siglip2 text encoder wrapper.
  # NOTE: output_tensor name is LOW CONFIDENCE — requires model inspection.
  # Specs for this class are marked pending until a Siglip2 ONNX fixture is available.
  # Per D-05: pure Ruby wrapper over GTE::Embedder.
  class Siglip2
    def initialize(model_path:, tokenizer_path: nil)
      resolved_tokenizer = tokenizer_path || File.join(File.dirname(model_path), "tokenizer.json")
      @embedder = GTE::Embedder.new(resolved_tokenizer, model_path, "siglip2")
    end

    # Embed a batch of texts. Returns Array<Array<Float>>.
    def embed(texts)
      @embedder.embed(Array(texts))
    end
  end
end
