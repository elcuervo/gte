# frozen_string_literal: true

module GTE
  # E5 model family wrapper.
  # Handles E5-specific defaults and query/passage prefix semantics (API-04, API-05).
  # Per D-05: pure Ruby wrapper over GTE::Embedder — no additional Rust structs.
  class E5
    # Initialize with model path. Tokenizer defaults to tokenizer.json in same directory.
    # Per D-06: prefix semantics implemented in Ruby, not Rust.
    def initialize(model_path:, tokenizer_path: nil, config: ModelConfig.e5)
      resolved_tokenizer = tokenizer_path || File.join(File.dirname(model_path), "tokenizer.json")
      @embedder = GTE::Embedder.new(
        resolved_tokenizer, model_path,
        config.max_length, config.output_tensor, config.mode.to_s, config.with_type_ids,
        config.with_attention_mask, config.num_threads, config.optimization_level
      )
    end

    # Embed a batch of texts without any prefix. Returns Array<Array<Float>>.
    def embed(texts)
      @embedder.embed(Array(texts))
    end

    # Embed a single query text, prepending "query: " prefix (API-04).
    # Returns Array<Float> (single embedding, L2-normalized).
    def embed_query(text)
      @embedder.embed(["query: #{text}"]).first
    end

    # Embed a single passage text, prepending "passage: " prefix (API-05).
    # Returns Array<Float> (single embedding, L2-normalized).
    def embed_passage(text)
      @embedder.embed(["passage: #{text}"]).first
    end
  end
end
