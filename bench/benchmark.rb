#!/usr/bin/env ruby
# frozen_string_literal: true

require "benchmark/ips"
require "gte"
require "fastembed"

model_dir = ENV.fetch("MODEL_DIR") { abort "Set MODEL_DIR to E5-small ONNX directory (e.g. tmp/multilingual-e5-small)" }
model_file = File.join(model_dir, "onnx", "model.onnx")
tokenizer_file = File.join(model_dir, "tokenizer.json")

abort "Model not found: #{model_file}" unless File.exist?(model_file)
abort "Tokenizer not found: #{tokenizer_file}" unless File.exist?(tokenizer_file)

puts "=== Same-model validation ==="
puts "Model:     #{model_file}"
puts "Tokenizer: #{tokenizer_file}"

# Both libraries load the EXACT same model and tokenizer files
gte_model = GTE::E5.new(model_path: model_file, tokenizer_path: tokenizer_file)
fe_model = Fastembed::TextEmbedding.new(
  local_model_dir: model_dir,
  model_file: "onnx/model.onnx",
  tokenizer_file: "tokenizer.json"
)

# Validate identical output
probe = ["query: benchmark validation probe"]
gte_emb = gte_model.embed(probe).first
fe_emb = fe_model.embed(probe).first

puts "GTE dim: #{gte_emb.size}, Fastembed dim: #{fe_emb.size}"
abort "Dimension mismatch! GTE=#{gte_emb.size} vs Fastembed=#{fe_emb.size}" if gte_emb.size != fe_emb.size

cosine = gte_emb.zip(fe_emb).sum { |a, b| a * b }
max_diff = gte_emb.zip(fe_emb).map { |a, b| (a - b).abs }.max
puts "Cosine similarity: #{cosine.round(6)}"
puts "Max absolute diff: #{max_diff}"
abort "Embeddings diverge! cosine=#{cosine}" if cosine < 0.9999

puts "\n=== Benchmarks ==="

TEXTS_1  = ["query: the quick brown fox"]
TEXTS_8  = Array.new(8)  { |i| "query: the quick brown fox #{i}" }
TEXTS_32 = Array.new(32) { |i| "query: the quick brown fox #{i}" }

[TEXTS_1, TEXTS_8, TEXTS_32].each do |texts|
  puts "\n--- Batch size: #{texts.size} ---"

  Benchmark.ips do |x|
    x.warmup = 5
    x.time = 10

    x.report("gte") { gte_model.embed(texts) }
    x.report("fastembed") { fe_model.embed(texts).to_a }

    x.compare!
  end
end
