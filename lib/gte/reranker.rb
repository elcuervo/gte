# frozen_string_literal: true

module GTE
  class Reranker
    class << self
      def config(model_dir)
        cfg = default_config(model_dir)

        if block_given?
          yielded = yield(cfg)
          cfg = yielded if yielded.is_a?(Config::Reranker)
        end

        build(cfg)
      end

      private

      def default_config(model_dir)
        Config::Reranker.new(
          model_dir: File.expand_path(model_dir),
          threads: 1,
          optimization_level: 3,
          model_name: nil,
          sigmoid: false,
          output_tensor: nil,
          max_length: nil,
          padding: nil,
          execution_providers: nil
        )
      end

      def build(cfg)
        new(
          cfg.model_dir,
          cfg.threads,
          cfg.optimization_level,
          cfg.model_name.to_s,
          cfg.sigmoid,
          cfg.output_tensor.to_s,
          cfg.max_length || 0,
          cfg.padding.to_s,
          cfg.execution_providers.to_s
        )
      end
    end

    def rerank(query:, candidates:)
      rows = Array(candidates).map(&:to_s)
      scores = score(query.to_s, rows)

      rows
        .each_with_index
        .map { |text, idx| { index: idx, score: scores[idx], text: text } }
        .sort_by { |row| -row[:score] }
    end
  end
end
