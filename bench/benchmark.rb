#!/usr/bin/env ruby
# frozen_string_literal: true

require "benchmark/ips"
require "gte"

BATCH_SIZES = [1, 8, 32, 128].freeze

def latency_stats(embedder, texts, iterations: 20)
  # Warmup
  embedder.embed(texts)

  times = iterations.times.map do
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    embedder.embed(texts)
    (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000
  end.sort

  { median: times[times.length / 2], p95: times[(times.length * 0.95).floor], p99: times[(times.length * 0.99).floor] }
end

def run_latency(name, embedder)
  puts "\n#{name} — Latency"
  puts "-" * 60
  BATCH_SIZES.each do |size|
    texts = Array.new(size) { |i| "This is benchmark text number #{i} for embedding" }
    stats = latency_stats(embedder, texts)
    printf "  batch=%3d  median=%7.2fms  p95=%7.2fms  p99=%7.2fms  per_item=%6.2fms\n",
           size, stats[:median], stats[:p95], stats[:p99], stats[:median] / size
  end
end

puts "GTE Ruby Benchmark"
puts "=" * 60

# E5
if (e5_path = ENV["GTE_MODEL_PATH"])
  e5 = GTE::E5.new(model_path: e5_path)
  run_latency("E5", e5)
end

# CLIP
if (clip_path = ENV["GTE_CLIP_MODEL_PATH"])
  clip_tok = ENV["GTE_CLIP_TOKENIZER_PATH"]
  clip = GTE::CLIP.new(model_path: clip_path, tokenizer_path: clip_tok)
  run_latency("CLIP", clip)
end

# Siglip2
if (siglip2_path = ENV["GTE_SIGLIP2_MODEL_PATH"])
  siglip2_tok = ENV["GTE_SIGLIP2_TOKENIZER_PATH"]
  siglip2 = GTE::Siglip2.new(model_path: siglip2_path, tokenizer_path: siglip2_tok)
  run_latency("Siglip2", siglip2)
end

# fastembed comparison (if both available)
begin
  require "fastembed"

  if e5_path
    model_dir = ENV.fetch("MODEL_DIR", File.dirname(e5_path))
    fe_model = Fastembed::TextEmbedding.new(
      local_model_dir: model_dir,
      model_file: File.basename(e5_path),
      tokenizer_file: "tokenizer.json"
    )

    # Validate same output
    probe = ["query: benchmark validation probe"]
    gte_emb = GTE::E5.new(model_path: e5_path).embed(probe).first
    fe_emb = fe_model.embed(probe).first

    if gte_emb.size == fe_emb.size
      cosine = gte_emb.zip(fe_emb).sum { |a, b| a * b }
      puts "\n\nfastembed cosine agreement: #{cosine.round(6)}"
    end

    run_latency("fastembed", fe_model)

    puts "\n\n--- Benchmark.ips comparison ---"
    [1, 8, 32].each do |size|
      texts = Array.new(size) { |i| "query: the quick brown fox #{i}" }
      puts "\nBatch size: #{size}"
      gte_model = GTE::E5.new(model_path: e5_path)
      Benchmark.ips do |x|
        x.warmup = 3
        x.time = 8
        x.report("gte")       { gte_model.embed(texts) }
        x.report("fastembed") { fe_model.embed(texts).to_a }
        x.compare!
      end
    end
  end
rescue LoadError
  puts "\nfastembed gem not available — skipping comparison"
end

puts "\nDone."
