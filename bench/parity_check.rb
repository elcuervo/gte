#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "gte"

MAX_ABS_DIFF_THRESHOLD = 1e-5
MIN_COSINE_THRESHOLD = 0.99999
DEFAULT_REFERENCE_PATH = File.expand_path("../tmp/parity_reference.json", __dir__)

MODEL_ENV = {
  "e5" => "GTE_MODEL_DIR",
  "clip" => "GTE_CLIP_DIR",
  "siglip2" => "GTE_SIGLIP2_DIR"
}.freeze

def ensure_reference_file(path)
  return if File.exist?(path)

  python_script = File.expand_path("benchmark_python.py", __dir__)
  stdout, stderr, status = Open3.capture3("python3", python_script, "--emit-reference", path)
  raise "failed generating Python references:\n#{stdout}\n#{stderr}" unless status.success?
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
  count = 0
  min_cosine = Float::INFINITY

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
    max_abs: max_abs,
    mean_abs: (count.zero? ? 0.0 : mean_abs / count),
    min_cosine: min_cosine
  }
end

reference_path = ENV.fetch("GTE_PARITY_REFERENCE_PATH", DEFAULT_REFERENCE_PATH)
ensure_reference_file(reference_path)
reference = JSON.parse(File.read(reference_path))

puts "GTE Ruby vs Python ORT parity"
puts "=" * 60
puts "reference: #{reference_path}"

failures = []

reference.each do |model_name, payload|
  env_var = MODEL_ENV.fetch(model_name)
  model_dir = ENV[env_var]
  if model_dir.nil? || model_dir.empty?
    puts "\n#{model_name}: skipped (#{env_var} not set)"
    next
  end

  texts = payload.fetch("texts")
  ref_embeddings = payload.fetch("embeddings")

  model = GTE.new(model_dir)
  actual_embeddings = model.embed(texts)

  stats = compare_embeddings(actual_embeddings, ref_embeddings)
  puts "\n#{model_name}: rows=#{texts.length} dim=#{actual_embeddings.first.length}"
  puts "  max_abs=#{stats[:max_abs]}"
  puts "  mean_abs=#{stats[:mean_abs]}"
  puts "  min_cosine=#{stats[:min_cosine]}"

  if stats[:max_abs] > MAX_ABS_DIFF_THRESHOLD || stats[:min_cosine] < MIN_COSINE_THRESHOLD
    failures << "#{model_name} failed thresholds (max_abs=#{stats[:max_abs]}, min_cosine=#{stats[:min_cosine]})"
  end
end

if failures.empty?
  puts "\nPASS: all compared models satisfy parity thresholds"
else
  warn "\nFAIL:"
  failures.each { |failure| warn "  - #{failure}" }
  exit 1
end
