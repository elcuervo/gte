# frozen_string_literal: true

begin
  require "gte/#{RUBY_VERSION.to_f}/gte"
rescue LoadError
  require 'gte/gte'
end

module GTE
  VERSION = File.read(File.expand_path('../VERSION', __dir__)).strip

  class Model
    def initialize(dir, num_threads: 0, optimization_level: 3)
      @embedder = GTE::Embedder.new(dir, num_threads, optimization_level)
    end

    def embed(texts)
      if texts.is_a?(String)
        @embedder.embed_one(texts)
      else
        @embedder.embed(Array(texts))
      end
    end

    def [](input)
      case input
      when String then embed(input).row(0)
      when Array  then embed(input)
      end
    end
  end

  def self.new(dir, num_threads: 0, optimization_level: 3)
    Model.new(dir, num_threads: num_threads, optimization_level: optimization_level)
  end
end
