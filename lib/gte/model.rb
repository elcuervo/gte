# frozen_string_literal: true

module GTE
  class Model
    attr_reader :config

    def initialize(config)
      raise ArgumentError, 'config must be a GTE::Config::Text' unless config.is_a?(Config::Text)

      @config = config
      @embedder = GTE::Embedder.new(
        config.model_dir,
        config.threads,
        config.optimization_level,
        config.model_name.to_s,
        config.normalize,
        config.output_tensor.to_s,
        config.max_length || 0
      )
    end

    def embed(texts)
      return @embedder.embed_one(texts) if texts.is_a?(String)

      @embedder.embed(Array(texts))
    end

    def [](input)
      case input
      when String then embed(input).row(0)
      when Array then embed(input)
      end
    end
  end
end
