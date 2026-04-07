# frozen_string_literal: true

module GTE
  # Global configuration for GTE module-level defaults.
  # Used by GTE.configure block and GTE.default memoized embedder.
  # Per D-07: pure Ruby pattern, no Rust singleton.
  class Configuration
    attr_accessor :model_path, :tokenizer_path, :model_config

    def initialize
      @model_config = ModelConfig.e5
    end
  end

  class << self
    # Configure global defaults. Example:
    #   GTE.configure { |c| c.model_path = "/path/to/model.onnx"; c.model_family = :e5 }
    def configure
      yield config
    end

    # Returns the current Configuration instance (memoized).
    def config
      @config ||= Configuration.new
    end

    # Returns a memoized default embedder built from current config.
    # Reset with GTE.reset_default! after config changes.
    def default
      @default ||= begin
        resolved_tokenizer = config.tokenizer_path || File.join(File.dirname(config.model_path), "tokenizer.json")
        mc = config.model_config
        Embedder.new(
          resolved_tokenizer, config.model_path,
          mc.max_length, mc.output_tensor, mc.mode.to_s, mc.with_type_ids,
          mc.with_attention_mask, mc.num_threads, mc.optimization_level
        )
      end
    end

    # Reset the memoized default embedder. Call after GTE.configure changes.
    def reset_default!
      @default = nil
    end
  end
end
