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
require 'gte/pool'
require 'gte/reranker'

module GTE
end
