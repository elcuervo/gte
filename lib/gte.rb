# frozen_string_literal: true

require_relative "gte/version"
require "gte/gte"
require_relative "gte/model"

module GTE
  def self.new(dir, num_threads: 0, optimization_level: 3)
    Model.new(dir, num_threads: num_threads, optimization_level: optimization_level)
  end
end
