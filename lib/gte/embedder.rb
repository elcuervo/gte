# frozen_string_literal: true

module GTE
  class Embedder
    class << self
      def config(model_dir)
        cfg = default_config(model_dir)
        cfg = yield(cfg) if block_given?
        from_config(cfg)
      end

      def from_config(config)
        new(
          config.model_dir,
          config.threads,
          config.optimization_level,
          config.model_name.to_s,
          config.normalize,
          config.output_tensor.to_s,
          config.max_length || 0,
          config.padding.to_s,
          config.execution_providers.to_s
        )
      end

      private

      def default_config(model_dir)
        Config::Text.new(
          model_dir: File.expand_path(model_dir),
          threads: 1,
          optimization_level: 3,
          model_name: nil,
          normalize: true,
          output_tensor: nil,
          max_length: nil,
          padding: nil,
          execution_providers: nil
        )
      end
    end
  end
end
