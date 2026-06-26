# frozen_string_literal: true

module GTE
  class Embedder
    DEFAULT_OPTIMIZATION_LEVEL = 3

    class << self
      def from_config(config)
        new(
          config.model_dir,
          config.optimization_level,
          config.model_name.to_s,
          config.output_tensor.to_s,
          config.max_length || 0,
          config.padding.to_s,
          config.execution_providers.to_s
        )
      end

      def default_config(model_dir)
        Config::Text.new(
          model_dir: File.expand_path(model_dir),
          optimization_level: DEFAULT_OPTIMIZATION_LEVEL,
          model_name: nil,
          output_tensor: nil,
          max_length: nil,
          padding: nil,
          execution_providers: nil
        )
      end
    end
  end
end
