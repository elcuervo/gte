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

  class Model
    def initialize(
      dir,
      num_threads: 0,
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

  class << self
    def new(
      dir,
      num_threads: 0,
      optimization: 3,
      model_name: nil,
      normalize: true,
      output_tensor: nil,
      max_length: nil
    )
      parsed_max_length = parse_max_length(max_length)
      key = [
        File.expand_path(dir),
        Integer(num_threads),
        Integer(optimization),
        model_name.to_s,
        normalize ? true : false,
        output_tensor.to_s,
        parsed_max_length || 0
      ].freeze

      @model_cache_mutex.synchronize { @model_cache[key] ||= build_model_for_key(key) }
    end

    private

    def parse_max_length(value)
      return nil if value.nil?

      parsed = Integer(value)
      raise ArgumentError, 'max_length must be greater than 0' if parsed <= 0

      parsed
    end

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
  end
end
