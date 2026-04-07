# frozen_string_literal: true

module GTE
  # Global configuration for GTE module-level defaults.
  # Used by GTE.configure block and GTE.default memoized embedder.
  # Per D-07: pure Ruby pattern, no Rust singleton.
  class Configuration
    attr_accessor :model_path, :tokenizer_path, :model_family

    def initialize
      @model_family = :e5
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
        klass = const_get(config.model_family.to_s.upcase)
        klass.new(
          model_path: config.model_path,
          tokenizer_path: config.tokenizer_path
        )
      end
    end

    # Reset the memoized default embedder. Call after GTE.configure changes.
    def reset_default!
      @default = nil
    end
  end
end
