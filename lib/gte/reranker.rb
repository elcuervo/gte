# frozen_string_literal: true

module GTE
  class Reranker
    class << self
      alias native_new new unless method_defined?(:native_new)

      def config(model_dir)
        cfg = Config::Reranker.new(
          model_dir: File.expand_path(model_dir),
          threads: 3,
          optimization_level: 3,
          model_name: nil,
          sigmoid: false,
          output_tensor: nil,
          max_length: nil
        )

        cfg = yield(cfg) if block_given?

        native_new(
          cfg.model_dir,
          cfg.threads,
          cfg.optimization_level,
          cfg.model_name.to_s,
          cfg.sigmoid,
          cfg.output_tensor.to_s,
          cfg.max_length || 0
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
