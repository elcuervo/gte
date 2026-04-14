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
    def initialize(dir, num_threads: 0, optimization_level: 3, model_name: nil, normalize: true)
      @embedder = GTE::Embedder.new(
        dir,
        num_threads,
        optimization_level,
        model_name.to_s,
        normalize
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
    def new(dir, num_threads: 0, optimization: 3, model_name: nil, normalize: true)
      key = [
        File.expand_path(dir),
        Integer(num_threads),
        Integer(optimization),
        model_name.to_s,
        normalize ? true : false
      ].freeze

      @model_cache_mutex.synchronize { @model_cache[key] ||= build_model_for_key(key) }
    end

    private

    def build_model_for_key(key)
      Model.new(
        key[0],
        num_threads: key[1],
        optimization_level: key[2],
        model_name: key[3].empty? ? nil : key[3],
        normalize: key[4]
      )
    end
  end
end
