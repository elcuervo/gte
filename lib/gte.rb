# frozen_string_literal: true

require 'gte/version'

begin
  require "gte/#{RUBY_VERSION.to_f}/gte"
rescue LoadError
  require 'gte/gte'
end

require 'gte/config'
require 'gte/embedder'
require 'gte/model'
require 'gte/reranker'

module GTE
  @model_cache_mutex = Mutex.new
  @model_cache = {}

  class << self
    def config(model_dir)
      cfg = Embedder.default_config(model_dir)

      cfg = yield(cfg) if block_given?

      @model_cache_mutex.synchronize do
        @model_cache[cache_key(cfg)] ||= Model.new(cfg)
      end
    end

    private

    def cache_key(cfg)
      cfg.to_h
    end
  end
end
