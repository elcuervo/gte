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
  def self.config(model_dir, &block)
    cfg = Embedder.default_config(model_dir)
    cfg = block.call(cfg) if block
    Model.new(cfg)
  end
end
