#!/usr/bin/env ruby
# frozen_string_literal: true

require "benchmark/ips"
require "gte"

BATCH_SIZES = [1, 8, 32, 128].freeze

def latency_stats(model, texts, iterations: 20)
  # Warmup
  model.embed(texts)

  times = iterations.times.map do
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    model.embed(texts)
    (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000
  end.sort

  { median: times[times.length / 2], p95: times[(times.length * 0.95).floor], p99: times[(times.length * 0.99).floor] }
end

def run_latency(name, model)
  puts "\n#{name} — Latency"
  puts "-" * 60
  BATCH_SIZES.each do |size|
    texts = Array.new(size) { |i| "This is benchmark text number #{i} for embedding" }
    stats = latency_stats(model, texts)
    printf "  batch=%3d  median=%7.2fms  p95=%7.2fms  p99=%7.2fms  per_item=%6.2fms\n",
           size, stats[:median], stats[:p95], stats[:p99], stats[:median] / size
  end
end

puts "GTE Ruby Benchmark"
puts "=" * 60

# E5
if (e5_dir = ENV["GTE_MODEL_DIR"])
  e5 = GTE.new(e5_dir)
  run_latency("E5", e5)

  # Print first embedding values for comparison with Python
  probe = ["query: benchmark validation probe"]
  emb = e5.embed(probe).first
  puts "\n  E5 first 5 values: #{emb.first(5).map { |v| v.round(6) }}"
end

# CLIP
if (clip_dir = ENV["GTE_CLIP_DIR"])
  clip = GTE.new(clip_dir)
  run_latency("CLIP", clip)

  emb = clip.embed(["a photo of a cat"]).first
  puts "\n  CLIP first 5 values: #{emb.first(5).map { |v| v.round(6) }}"
end

# Siglip2
if (siglip2_dir = ENV["GTE_SIGLIP2_DIR"])
  siglip2 = GTE.new(siglip2_dir)
  run_latency("Siglip2", siglip2)

  emb = siglip2.embed(["a photo of a cat"]).first
  puts "\n  Siglip2 first 5 values: #{emb.first(5).map { |v| v.round(6) }}"
end

# fastembed comparison (if both available)
begin
  require "fastembed"

  if e5_dir
    fe_model = Fastembed::TextEmbedding.new(
      local_model_dir: e5_dir,
      model_file: "onnx/model.onnx",
      tokenizer_file: "tokenizer.json"
    )

    # Validate same output
    probe = ["query: benchmark validation probe"]
    gte_emb = e5.embed(probe).first
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
      Benchmark.ips do |x|
        x.warmup = 3
        x.time = 8
        x.report("gte")       { e5.embed(texts) }
        x.report("fastembed") { fe_model.embed(texts).to_a }
        x.compare!
      end
    end
  end
rescue LoadError
  puts "\nfastembed gem not available — skipping comparison"
end

puts "\nDone."
