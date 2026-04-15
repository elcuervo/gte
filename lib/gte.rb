# frozen_string_literal: true

begin
  require "gte/#{RUBY_VERSION.to_f}/gte"
rescue LoadError
  require 'gte/gte'
end

module GTE
  VERSION = File.read(File.expand_path('../VERSION', __dir__)).strip

  @model_cache_mutex = Mutex.new
  @model_cache = {}

  # rubocop:disable Metrics/ParameterLists
  class Model
    def initialize(
      dir,
      num_threads: 3,
      optimization_level: 3,
      model_name: nil,
      normalize: true,
      output_tensor: nil,
      max_length: nil
    )
      @embedder = GTE::Embedder.new(
        dir,
        num_threads,
        optimization_level,
        model_name.to_s,
        normalize,
        output_tensor.to_s,
        max_length || 0
      )
    end

    def embed(texts)
      return @embedder.embed_one(texts) if texts.is_a?(String)

      @embedder.embed(Array(texts))
    end

    def [](input)
      case input
      when String then embed(input).row(0)
      when Array  then embed(input)
      end
    end
  end

  class RerankerModel
    def initialize(
      dir,
      num_threads: 3,
      optimization_level: 3,
      model_name: nil,
      sigmoid: false,
      output_tensor: nil,
      max_length: nil
    )
      @reranker = GTE::Reranker.new(
        dir,
        num_threads,
        optimization_level,
        model_name.to_s,
        sigmoid,
        output_tensor.to_s,
        max_length || 0
      )
    end

    def score(query:, candidates:)
      @reranker.score(query.to_s, Array(candidates).map(&:to_s))
    end

    def rerank(query:, candidates:)
      rows = Array(candidates).map(&:to_s)
      scores = score(query: query, candidates: rows)
      rows.each_with_index.map { |text, idx| { index: idx, score: scores[idx], text: text } }
                          .sort_by { |row| -row[:score] }
    end
  end

  class Reranker
    def rerank(query:, candidates:)
      rows = Array(candidates).map(&:to_s)
      scores = score(query.to_s, rows)
      rows.each_with_index.map { |text, idx| { index: idx, score: scores[idx], text: text } }
                          .sort_by { |row| -row[:score] }
    end
  end
  class << self
    def new(
      dir,
      num_threads: 3,
      optimization: 3,
      model_name: nil,
      normalize: true,
      output_tensor: nil,
      max_length: nil
    )
      threads = validate_num_threads!(num_threads)
      max_len = validate_max_length!(max_length)
      key = [
        File.expand_path(dir),
        threads,
        Integer(optimization),
        model_name.to_s,
        normalize ? true : false,
        output_tensor.to_s,
        max_len || 0
      ].freeze

      @model_cache_mutex.synchronize { @model_cache[key] ||= build_model_for_key(key) }
    end

    def reranker(
      dir,
      num_threads: 3,
      optimization: 3,
      model_name: nil,
      sigmoid: false,
      output_tensor: nil,
      max_length: nil
    )
      threads = validate_num_threads!(num_threads)
      max_len = validate_max_length!(max_length)
      RerankerModel.new(
        dir,
        num_threads: threads,
        optimization_level: optimization,
        model_name: model_name,
        sigmoid: sigmoid ? true : false,
        output_tensor: output_tensor,
        max_length: max_len
      )
    end

    private

    def build_model_for_key(key)
      Model.new(
        key[0],
        num_threads: key[1],
        optimization_level: key[2],
        model_name: key[3].empty? ? nil : key[3],
        normalize: key[4],
        output_tensor: key[5].empty? ? nil : key[5],
        max_length: key[6].zero? ? nil : key[6]
      )
    end

    def validate_num_threads!(num_threads)
      value = Integer(num_threads)
      raise ArgumentError, 'num_threads must be >= 0' if value.negative?

      value
    end

    def validate_max_length!(max_length)
      return nil if max_length.nil?

      value = Integer(max_length)
      raise ArgumentError, 'max_length must be > 0' if value <= 0

      value
    end
  end
  # rubocop:enable Metrics/ParameterLists
end
