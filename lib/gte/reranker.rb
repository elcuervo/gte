# frozen_string_literal: true

module GTE
  class Reranker
    class << self
      alias_method :native_new, :new

      def new(model_dir, &block)
        cfg = default_config(model_dir)
        cfg = block.call(cfg) if block
        native_new(
          cfg.model_dir,
          cfg.optimization_level,
          cfg.model_name.to_s,
          cfg.sigmoid,
          cfg.output_tensor.to_s,
          cfg.max_length || 0,
          cfg.padding.to_s,
          cfg.execution_providers.to_s
        )
      end

      private

      def default_config(model_dir)
        Config::Reranker.new(
          model_dir: File.expand_path(model_dir),
          optimization_level: 3,
          model_name: nil,
          sigmoid: false,
          output_tensor: nil,
          max_length: nil,
          padding: nil,
          execution_providers: nil
        )
      end
    end

  end
end
