# frozen_string_literal: true

require 'gte/version'

begin
  require "gte/#{RUBY_VERSION.to_f}/gte"
rescue LoadError
  require 'gte/gte'
end

require 'gte/config'
require 'gte/model'
require 'gte/reranker'

module GTE
  @model_cache_mutex = Mutex.new
  @model_cache = {}

  class << self
    def config(model_dir)
      cfg = Config::Text.new(
        model_dir: File.expand_path(model_dir),
        threads: 3,
        optimization_level: 3,
        model_name: nil,
        normalize: true,
        output_tensor: nil,
        max_length: nil
      )

      cfg = yield(cfg) if block_given?

      @model_cache_mutex.synchronize { @model_cache[cache_key(cfg)] ||= Model.new(cfg) }
    end

    private

    def cache_key(cfg)
      [
        cfg.model_dir,
        cfg.threads,
        cfg.optimization_level,
        cfg.model_name,
        cfg.normalize,
        cfg.output_tensor,
        cfg.max_length
      ]
    end
  end
end
