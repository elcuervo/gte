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
      cfg = Config::Text.new(
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
