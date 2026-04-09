#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "optparse"
require "pathname"
require "time"

require "gte"
require_relative "pure_ruby_runtime"

ROOT = File.expand_path("..", __dir__)
DEFAULT_OUTPUT_DIR = File.expand_path("results", __dir__)
DEFAULT_ITERATIONS = 20
BATCH_SIZES = [1, 8, 32, 128].freeze
DEFAULT_MAX_ABS = 1e-5
DEFAULT_MIN_COS = 0.99999
DEFAULT_MIN_SPEEDUP = 3.0

MODELS = {
  "e5" => {
    "label" => "E5 multilingual small",
    "env_var" => "GTE_MODEL_DIR",
    "texts" => [
      "query: benchmark validation probe",
      "query: machine learning basics",
      "passage: gradient descent updates model parameters"
    ]
  },
  "clip" => {
    "label" => "CLIP ViT-B/32 text encoder",
    "env_var" => "GTE_CLIP_DIR",
    "texts" => [
      "a photo of a cat",
      "a picture of a kitten",
      "a blueprint of a skyscraper"
    ]
  },
  "siglip2" => {
    "label" => "Siglip2 base text encoder",
    "env_var" => "GTE_SIGLIP2_DIR",
    "texts" => [
      "a photo of a cat",
      "a photo of a dog",
      "a geometric abstract logo"
    ]
  }
}.freeze

def default_output_path
  timestamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
  File.join(DEFAULT_OUTPUT_DIR, "pure_ruby_vs_gte_#{timestamp}.json")
end

def resolve_models
  MODELS.each_with_object({}) do |(key, cfg), out|
    dir = ENV[cfg.fetch("env_var")]
    next if dir.nil? || dir.empty?

    expanded = File.expand_path(dir, ROOT)
    next unless Dir.exist?(expanded)

    out[key] = cfg.merge("dir" => expanded)
  end
end

def cosine_similarity(a, b)
  dot = a.zip(b).sum { |x, y| x * y }
  norm_a = Math.sqrt(a.sum { |v| v * v })
  norm_b = Math.sqrt(b.sum { |v| v * v })
  return 0.0 if norm_a.zero? || norm_b.zero?

  dot / (norm_a * norm_b)
end

def compare_embeddings(actual, reference)
  raise "row count mismatch: #{actual.length} vs #{reference.length}" unless actual.length == reference.length

  max_abs = 0.0
  mean_abs = 0.0
  min_cosine = Float::INFINITY
  count = 0

  actual.zip(reference).each do |act_row, ref_row|
    raise "dimension mismatch: #{act_row.length} vs #{ref_row.length}" unless act_row.length == ref_row.length

    act_row.zip(ref_row).each do |act, ref|
      diff = (act - ref).abs
      max_abs = diff if diff > max_abs
      mean_abs += diff
      count += 1
    end

    cos = cosine_similarity(act_row, ref_row)
    min_cosine = cos if cos < min_cosine
  end

  {
    "max_abs" => max_abs,
    "mean_abs" => (count.zero? ? 0.0 : mean_abs / count),
    "min_cosine" => min_cosine
  }
end

def materialize_embeddings(result)
  return result if result.is_a?(Array)
  return result.to_a if result.respond_to?(:to_a)

  result
end

def percentile(sorted, p)
  sorted[(sorted.length * p).floor]
end

def latency_summary(samples_ms)
  sorted = samples_ms.sort
  {
    "median_ms" => sorted[sorted.length / 2],
    "p95_ms" => percentile(sorted, 0.95),
    "p99_ms" => percentile(sorted, 0.99)
  }
end

def benchmark_pair(gte_model, pure_model, texts, iterations)
  gte_model.embed(texts)
  pure_model.embed(texts)

  gte_times = []
  pure_times = []

  iterations.times do |idx|
    if idx.even?
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      gte_model.embed(texts)
      gte_times << (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000.0

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      pure_model.embed(texts)
      pure_times << (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000.0
    else
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      pure_model.embed(texts)
      pure_times << (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000.0

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      gte_model.embed(texts)
      gte_times << (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000.0
    end
  end

  {
    "gte" => latency_summary(gte_times),
    "pure_ruby" => latency_summary(pure_times)
  }
end

options = {
  output: default_output_path,
  iterations: DEFAULT_ITERATIONS,
  max_abs: DEFAULT_MAX_ABS,
  min_cos: DEFAULT_MIN_COS,
  min_speedup: DEFAULT_MIN_SPEEDUP
}

OptionParser.new do |opts|
  opts.on("--output PATH") { |value| options[:output] = File.expand_path(value, ROOT) }
  opts.on("--iterations N", Integer) { |value| options[:iterations] = value }
  opts.on("--max-abs FLOAT", Float) { |value| options[:max_abs] = value }
  opts.on("--min-cos FLOAT", Float) { |value| options[:min_cos] = value }
  opts.on("--min-speedup FLOAT", Float) { |value| options[:min_speedup] = value }
end.parse!(ARGV)

if options[:iterations] <= 0
  warn("iterations must be > 0")
  exit 1
end

resolved = resolve_models
if resolved.empty?
  warn("no model directories configured via GTE_MODEL_DIR/GTE_CLIP_DIR/GTE_SIGLIP2_DIR")
  exit 1
end

puts "Pure Ruby (onnxruntime + tokenizers) vs GTE"
puts "=" * 60
puts "iterations: #{options[:iterations]}"
puts "thresholds: max_abs<=#{options[:max_abs]} min_cos>=#{options[:min_cos]} min_speedup>=#{options[:min_speedup]}x"

payload = {
  "version" => 1,
  "generated_at" => Time.now.utc.iso8601,
  "ruby_version" => RUBY_VERSION,
  "platform" => RUBY_PLATFORM,
  "iterations" => options[:iterations],
  "batch_sizes" => BATCH_SIZES,
  "thresholds" => {
    "max_abs" => options[:max_abs],
    "min_cos" => options[:min_cos],
    "min_speedup" => options[:min_speedup]
  },
  "models" => {}
}

correctness_failures = []
speed_failures = []

resolved.each do |key, cfg|
  label = cfg.fetch("label")
  model_dir = cfg.fetch("dir")

  puts "\n#{label} (#{key})"
  puts "  dir: #{Pathname.new(model_dir).relative_path_from(Pathname.new(ROOT))}"

  gte_model = GTE.new(model_dir)
  pure_model = PureRubyTextEmbedding::TextEncoder.new(model_dir: model_dir)

  probe_texts = cfg.fetch("texts")
  gte_embeddings = materialize_embeddings(gte_model.embed(probe_texts))
  pure_embeddings = pure_model.embed(probe_texts)

  correctness = compare_embeddings(pure_embeddings, gte_embeddings)
  correctness["rows"] = probe_texts.length
  correctness["dim"] = pure_embeddings.first&.length || 0

  puts format("  correctness: max_abs=%<max>.9f mean_abs=%<mean>.9f min_cosine=%<cos>.9f",
              max: correctness.fetch("max_abs"),
              mean: correctness.fetch("mean_abs"),
              cos: correctness.fetch("min_cosine"))

  if correctness.fetch("max_abs") > options[:max_abs] || correctness.fetch("min_cosine") < options[:min_cos]
    correctness_failures << "#{key} failed correctness thresholds"
  end

  batches = {}
  puts "  benchmarks:"
  BATCH_SIZES.each do |size|
    texts = Array.new(size) { |i| "benchmark text #{i} for #{key}" }
    stats = benchmark_pair(gte_model, pure_model, texts, options[:iterations])

    gte_stats = stats.fetch("gte")
    pure_stats = stats.fetch("pure_ruby")
    ratio = pure_stats.fetch("median_ms") / gte_stats.fetch("median_ms")

    gte_stats["per_item_ms"] = gte_stats.fetch("median_ms") / size
    pure_stats["per_item_ms"] = pure_stats.fetch("median_ms") / size

    puts format("    batch=%<size>3d gte=%<gte>7.2fms pure=%<pure>7.2fms ratio=%<ratio>.2fx",
                size: size,
                gte: gte_stats.fetch("median_ms"),
                pure: pure_stats.fetch("median_ms"),
                ratio: ratio)

    batches["batch_#{size}"] = {
      "gte" => gte_stats,
      "pure_ruby" => pure_stats,
      "ratio_pure_over_gte" => ratio
    }
  end

  batch1_ratio = batches.dig("batch_1", "ratio_pure_over_gte").to_f
  if batch1_ratio < options[:min_speedup]
    speed_failures << "#{key} batch_1 ratio #{batch1_ratio.round(2)}x < #{options[:min_speedup]}x"
  end

  payload.fetch("models")[key] = {
    "label" => label,
    "dir" => Pathname.new(model_dir).relative_path_from(Pathname.new(ROOT)).to_s,
    "correctness" => correctness,
    "benchmark" => batches
  }
end

FileUtils.mkdir_p(File.dirname(options[:output]))
File.write(options[:output], JSON.pretty_generate(payload) + "\n")
puts "\nWrote compare results: #{Pathname.new(options[:output]).relative_path_from(Pathname.new(ROOT))}"

if correctness_failures.empty?
  puts "PASS: correctness thresholds satisfied"
else
  warn "FAIL: correctness threshold failures"
  correctness_failures.each { |f| warn "  - #{f}" }
  exit 1
end

if speed_failures.empty?
  puts "PASS: batch_1 speed target met"
else
  warn "FAIL: batch_1 speed target not met"
  speed_failures.each { |f| warn "  - #{f}" }
  exit 1
end
