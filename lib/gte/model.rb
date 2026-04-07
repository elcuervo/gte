# frozen_string_literal: true

module GTE
  class Model
    def initialize(dir, num_threads: 0, optimization_level: 3)
      @embedder = GTE::Embedder.new(dir, num_threads, optimization_level)
    end

    # Embed one or more texts. Always returns Array<Array<Float>>.
    def embed(texts)
      @embedder.embed(Array(texts))
    end

    # Shortcut: single string → single embedding vector; array → batch.
    def [](input)
      case input
      when String then embed([input]).first
      when Array  then embed(input)
      end
    end
  end
end
