#!/usr/bin/env ruby
# frozen_string_literal: true

require "benchmark/ips"
require "gte"
require "fastembed"

model_path = ENV.fetch("MODEL_PATH") { abort "Set MODEL_PATH to E5-small ONNX directory" }

# Initialize models
gte_model = GTE::E5.new(model_path: model_path)
fe_model = Fastembed::TextEmbedding.new(model_name: "intfloat/multilingual-e5-small")

# Sanity check: verify embedding dimensions match
gte_dim = gte_model.embed(["query: test"]).first.size
fe_dim = fe_model.embed(["query: test"]).first.size
puts "GTE dimension: #{gte_dim}, Fastembed dimension: #{fe_dim}"
abort "Dimension mismatch! GTE=#{gte_dim} vs Fastembed=#{fe_dim}" if gte_dim != fe_dim

# Test texts at different batch sizes
TEXTS_1  = ["query: the quick brown fox"]
TEXTS_8  = Array.new(8)  { |i| "query: the quick brown fox #{i}" }
TEXTS_32 = Array.new(32) { |i| "query: the quick brown fox #{i}" }

[TEXTS_1, TEXTS_8, TEXTS_32].each do |texts|
  puts "\n=== Batch size: #{texts.size} ==="

  Benchmark.ips do |x|
    x.warmup = 5
    x.time = 10

    x.report("gte") { gte_model.embed(texts) }
    x.report("fastembed") { fe_model.embed(texts).to_a }

    x.compare!
  end
end
