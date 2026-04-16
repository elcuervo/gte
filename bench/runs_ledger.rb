#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'optparse'
require 'pathname'
require 'time'

ROOT = File.expand_path('..', __dir__)
DEFAULT_RUNS_PATH = File.expand_path('RUNS.md', ROOT)
DEFAULT_TOLERANCE = 0.15
EXPECTED_MODELS = %w[e5 clip siglip2].freeze
GOAL_METRIC = 'response_time_p95'

class LedgerError < StandardError; end

def load_result(path)
  JSON.parse(File.read(path))
rescue Errno::ENOENT
  raise LedgerError, "result file not found: #{path}"
rescue JSON::ParserError => e
  raise LedgerError, "invalid result JSON at #{path}: #{e.message}"
end

def load_entries(runs_path)
  return [] unless File.exist?(runs_path)

  content = File.read(runs_path)
  blocks = content.scan(/```json\n(.*?)\n```/m).flatten
  blocks.filter_map do |block|
    JSON.parse(block)
  rescue JSON::ParserError
    nil
  end
end

def previous_entry(entries, result)
  generated_at = result.fetch('generated_at')
  concurrency = result.fetch('concurrency', 16)
  iterations = result.fetch('iterations', 0)
  run_samples = result.fetch('run_samples', 1)
  entries.reverse.find do |entry|
    entry['kind'] == 'puma_compare_run' &&
      entry['generated_at'] != generated_at &&
      entry.dig('thresholds', 'goal_metric') == GOAL_METRIC &&
      entry['concurrency'] == concurrency &&
      entry['iterations'] == iterations &&
      entry['run_samples'] == run_samples
  end
end

def duplicate_entry?(entries, result)
  generated_at = result.fetch('generated_at')
  git_sha = result.fetch('git_sha', nil)
  entries.any? do |entry|
    entry['kind'] == 'puma_compare_run' &&
      entry['generated_at'] == generated_at &&
      (git_sha.nil? || entry['git_sha'] == git_sha)
  end
end

def model_metrics(result, key)
  model = result.fetch('models').fetch(key)
  puma = model.fetch('puma_like')
  gte = puma.fetch('gte').fetch('aggregate')
  pure = puma.fetch('pure_ruby').fetch('aggregate')

  {
    'gte_response_p95_ms' => gte.fetch('response_time').fetch('p95_ms'),
    'pure_response_p95_ms' => pure.fetch('response_time').fetch('p95_ms'),
    'response_ratio_p95' => puma.fetch('ratio_pure_over_gte').fetch('response_p95'),
    'gte_response_median_ms' => gte.fetch('response_time').fetch('median_ms'),
    'response_ratio_median' => puma.fetch('ratio_pure_over_gte').fetch('response_median'),
    'gte_service_p95_ms' => gte.fetch('service_time').fetch('p95_ms'),
    'pure_service_p95_ms' => pure.fetch('service_time').fetch('p95_ms'),
    'service_ratio_p95' => puma.fetch('ratio_pure_over_gte').fetch('service_p95'),
    'gte_throughput_rps' => gte.fetch('throughput_rps'),
    'pure_throughput_rps' => pure.fetch('throughput_rps')
  }
end

def build_entry(result, previous:, tolerance:)
  missing = EXPECTED_MODELS - result.fetch('models').keys
  raise LedgerError, "result missing expected models: #{missing.join(', ')}" unless missing.empty?

  min_ratio = result.fetch('thresholds', {}).fetch('min_p95_ratio', 2.0).to_f

  metrics = {}
  regressions = {}
  ratio_pass = true
  regression_pass = true

  EXPECTED_MODELS.each do |key|
    current = model_metrics(result, key)
    metrics[key] = current

    ratio_pass &&= current.fetch('response_ratio_p95') >= min_ratio

    next unless previous

    prev_value = previous.dig('metrics', key, 'gte_response_p95_ms')
    next unless prev_value

    allowed = prev_value.to_f * (1.0 + tolerance)
    regressed = current.fetch('gte_response_p95_ms') > allowed
    regressions[key] = {
      'previous_gte_response_p95_ms' => prev_value,
      'current_gte_response_p95_ms' => current.fetch('gte_response_p95_ms'),
      'allowed_gte_response_p95_ms' => allowed,
      'regressed' => regressed
    }
    regression_pass &&= !regressed
  end

  {
    'kind' => 'puma_compare_run',
    'recorded_at' => Time.now.utc.iso8601,
    'generated_at' => result.fetch('generated_at'),
    'gem_version' => result.fetch('gem_version', 'unknown'),
    'git_sha' => result.fetch('git_sha', 'unknown'),
    'platform' => result.fetch('platform', RUBY_PLATFORM),
    'ruby_version' => result.fetch('ruby_version', RUBY_VERSION),
    'mode' => result.fetch('mode', 'puma_like_in_process'),
    'concurrency' => result.fetch('concurrency', 16),
    'iterations' => result.fetch('iterations', 0),
    'run_samples' => result.fetch('run_samples', 1),
    'thresholds' => {
      'goal_metric' => GOAL_METRIC,
      'sample_aggregation' => result.dig('thresholds', 'sample_aggregation') || 'median',
      'min_p95_ratio' => min_ratio,
      'regression_tolerance' => tolerance
    },
    'status' => {
      'goal_response_p95_ratio_all_models' => ratio_pass,
      'regression_vs_previous' => previous ? regression_pass : true,
      'regression_baseline' => previous ? 'previous_run' : 'none'
    },
    'metrics' => metrics,
    'regressions' => regressions
  }
end

def append_entry(runs_path, entry)
  unless File.exist?(runs_path)
    File.write(runs_path, <<~MD)
      # RUNS

      Performance run ledger for Puma-like single-request concurrency benchmarks.

      - Goal metric: response-time p95 (median of 3 runs).
      - Goal: all models must satisfy `pure_response_p95 / gte_response_p95 >= 1.95`.
      - Regression: compare against previous run; fail if GTE response-time p95 increases by more than 15%.
      - Primary workload: in-process thread pool with concurrency `16`.
    MD
  end

  status_goal = entry.dig('status', 'goal_response_p95_ratio_all_models') ? 'PASS' : 'FAIL'
  status_regression = entry.dig('status', 'regression_vs_previous') ? 'PASS' : 'FAIL'

  File.open(runs_path, 'a') do |f|
    f.puts
    f.puts "## #{entry.fetch('generated_at')} | v#{entry.fetch('gem_version')} | #{entry.fetch('git_sha')}"
    f.puts "- Goal (response-time p95 ratio all models): #{status_goal}"
    f.puts "- Regression vs previous run (GTE response-time p95 <= +#{(entry.dig('thresholds',
                                                                                 'regression_tolerance') * 100).round(1)}%): #{status_regression}"
    f.puts
    f.puts '```json'
    f.puts JSON.pretty_generate(entry)
    f.puts '```'
  end
end

def current_version
  File.read(File.expand_path('../VERSION', __dir__)).strip
end

def check_entry!(entry, goal_only: false)
  failures = []
  unless entry.dig('status', 'goal_response_p95_ratio_all_models')
    failures << 'goal failure: one or more models did not hit response-time p95 2x ratio'
  end

  unless goal_only || entry.dig('status', 'regression_vs_previous')
    failures << 'regression failure: one or more models regressed above allowed response-time p95 tolerance'
  end

  failures
end

def latest_result_path
  Dir.glob(File.expand_path('results/puma_compare_*.json', __dir__)).max
end

command = ARGV.shift
case command
when 'append'
  options = {
    runs: DEFAULT_RUNS_PATH,
    tolerance: DEFAULT_TOLERANCE,
    result: nil
  }

  OptionParser.new do |opts|
    opts.on('--result PATH') { |value| options[:result] = File.expand_path(value, ROOT) }
    opts.on('--runs PATH') { |value| options[:runs] = File.expand_path(value, ROOT) }
    opts.on('--max-regression FLOAT', Float) { |value| options[:tolerance] = value }
    opts.on('--latest') { options[:result] = latest_result_path }
  end.parse!(ARGV)

  raise LedgerError, '--result PATH or --latest is required' unless options[:result]

  result = load_result(options[:result])
  entries = load_entries(options[:runs])
  if duplicate_entry?(entries, result)
    puts "Run already recorded in #{Pathname.new(options[:runs]).relative_path_from(Pathname.new(ROOT))}"
    exit 0
  end

  previous = previous_entry(entries, result)
  entry = build_entry(result, previous: previous, tolerance: options[:tolerance])

  append_entry(options[:runs], entry)
  puts "Appended run to #{Pathname.new(options[:runs]).relative_path_from(Pathname.new(ROOT))}"
  puts "goal=#{if entry.dig('status',
                            'goal_response_p95_ratio_all_models')
                 'PASS'
               else
                 'FAIL'
               end} regression=#{if entry.dig('status',
                                              'regression_vs_previous')
                                   'PASS'
                                 else
                                   'FAIL'
                                 end}"
when 'check'
  options = {
    runs: DEFAULT_RUNS_PATH,
    tolerance: DEFAULT_TOLERANCE,
    result: nil,
    require_current_version: false,
    goal_only: true
  }

  OptionParser.new do |opts|
    opts.on('--result PATH') { |value| options[:result] = File.expand_path(value, ROOT) }
    opts.on('--runs PATH') { |value| options[:runs] = File.expand_path(value, ROOT) }
    opts.on('--max-regression FLOAT', Float) { |value| options[:tolerance] = value }
    opts.on('--latest') { options[:result] = latest_result_path }
    opts.on('--[no-]require-current-version') { |value| options[:require_current_version] = value }
    opts.on('--[no-]goal-only') { |value| options[:goal_only] = value }
  end.parse!(ARGV)

  raise LedgerError, '--result PATH or --latest is required' unless options[:result]

  result = load_result(options[:result])
  entries = options[:goal_only] ? [] : load_entries(options[:runs])
  previous = options[:goal_only] ? nil : previous_entry(entries, result)
  entry = build_entry(result, previous: previous, tolerance: options[:tolerance])

  failures = check_entry!(entry, goal_only: options[:goal_only])

  if options[:require_current_version] && !options[:goal_only]
    versions = entries.filter_map { |entry_item| entry_item['gem_version'] }
    versions << result.fetch('gem_version', nil)
    unless versions.compact.include?(current_version)
      failures << "version coverage failure: RUNS.md has no run for current VERSION=#{current_version}"
    end
  end

  if failures.empty?
    if options[:goal_only]
      puts 'PASS: goal checks succeeded'
    else
      puts 'PASS: goal and regression checks succeeded'
    end
  else
    warn 'FAIL: run checks failed'
    failures.each { |failure| warn "  - #{failure}" }
    exit 1
  end
when 'verify-current-version'
  options = { runs: DEFAULT_RUNS_PATH }
  OptionParser.new do |opts|
    opts.on('--runs PATH') { |value| options[:runs] = File.expand_path(value, ROOT) }
  end.parse!(ARGV)

  entries = load_entries(options[:runs])
  versions = entries.filter_map { |entry_item| entry_item['gem_version'] }
  if versions.include?(current_version)
    puts "PASS: RUNS.md contains current VERSION=#{current_version}"
  else
    warn "FAIL: RUNS.md missing current VERSION=#{current_version}"
    exit 1
  end
else
  warn <<~USAGE
    Usage:
      ruby bench/runs_ledger.rb append --result PATH [--runs RUNS.md] [--max-regression 0.05]
      ruby bench/runs_ledger.rb append --latest [--runs RUNS.md]
      ruby bench/runs_ledger.rb check --result PATH [--runs RUNS.md] [--max-regression 0.05]
      ruby bench/runs_ledger.rb check --latest [--runs RUNS.md]
      ruby bench/runs_ledger.rb verify-current-version [--runs RUNS.md]
  USAGE
  exit 1
end
