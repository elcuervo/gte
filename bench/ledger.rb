#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'optparse'
require 'pathname'
require 'time'

module Bench
  # rubocop:disable Metrics/ModuleLength
  module RunsLedger
    ROOT = File.expand_path('..', __dir__)
    DEFAULT_RUNS_PATH = File.expand_path('RUNS.md', ROOT)
    DEFAULT_TOLERANCE = 0.15
    EXPECTED_MODELS = %w[e5 clip siglip2].freeze
    GOAL_METRIC = 'response_time_p95'

    class LedgerError < StandardError; end

    module_function

    def load_result(path)
      JSON.parse(File.read(path))
    rescue Errno::ENOENT
      raise LedgerError, "result file not found: #{path}"
    rescue JSON::ParserError => e
      raise LedgerError, "invalid result JSON at #{path}: #{e.message}"
    end

    def load_entries(runs_path)
      return [] unless File.exist?(runs_path)

      File.read(runs_path).scan(/```json\n(.*?)\n```/m).flatten.filter_map do |block|
        JSON.parse(block)
      rescue JSON::ParserError
        nil
      end
    end

    def previous_entry(entries, result)
      generated_at = result.fetch('generated_at')
      puma = result.fetch('puma_like', {})

      entries.reverse.find do |entry|
        entry['kind'] == 'puma_compare_run' &&
          entry['generated_at'] != generated_at &&
          entry.dig('thresholds', 'goal_metric') == GOAL_METRIC &&
          entry['concurrency'] == puma.fetch('concurrency', 16) &&
          entry['iterations'] == puma.fetch('iterations', 0) &&
          entry['run_samples'] == puma.fetch('run_samples', 1)
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
      scenario = result.fetch('models').fetch(key).fetch('scenarios').fetch('puma_like_single_request')
      gte = scenario.fetch('by_adapter').fetch('gte').fetch('aggregate')
      competitors = scenario.fetch('gate').fetch('comparisons')

      {
        'gte_response_p95_ms' => gte.fetch('response_time').fetch('p95_ms'),
        'gte_response_median_ms' => gte.fetch('response_time').fetch('median_ms'),
        'gte_service_p95_ms' => gte.fetch('service_time').fetch('p95_ms'),
        'gte_throughput_rps' => gte.fetch('throughput_rps'),
        'minimum_ratio_p95' => scenario.fetch('gate').fetch('minimum_ratio_over_gte'),
        'competitors' => competitors
      }
    end

    def build_entry(result, previous:, tolerance:)
      missing = EXPECTED_MODELS - result.fetch('models').keys
      raise LedgerError, "result missing expected models: #{missing.join(', ')}" unless missing.empty?

      min_ratio = result.fetch('thresholds', {}).fetch('min_p95_ratio', 1.0).to_f
      metrics = {}
      regressions = {}
      ratio_pass = true
      regression_pass = true

      EXPECTED_MODELS.each do |key|
        current = model_metrics(result, key)
        metrics[key] = current
        ratio_pass &&= current.fetch('minimum_ratio_p95') >= min_ratio

        next unless previous

        previous_value = previous.dig('metrics', key, 'gte_response_p95_ms')
        next unless previous_value

        allowed = previous_value.to_f * (1.0 + tolerance)
        regressed = current.fetch('gte_response_p95_ms') > allowed
        regressions[key] = {
          'previous_gte_response_p95_ms' => previous_value,
          'current_gte_response_p95_ms' => current.fetch('gte_response_p95_ms'),
          'allowed_gte_response_p95_ms' => allowed,
          'regressed' => regressed
        }
        regression_pass &&= !regressed
      end

      puma = result.fetch('puma_like', {})
      {
        'kind' => 'puma_compare_run',
        'recorded_at' => Time.now.utc.iso8601,
        'generated_at' => result.fetch('generated_at'),
        'gem_version' => result.fetch('gem_version', 'unknown'),
        'git_sha' => result.fetch('git_sha', 'unknown'),
        'platform' => result.fetch('platform', RUBY_PLATFORM),
        'ruby_version' => result.fetch('ruby_version', RUBY_VERSION),
        'mode' => 'puma_like_in_process',
        'concurrency' => puma.fetch('concurrency', 16),
        'iterations' => puma.fetch('iterations', 0),
        'run_samples' => puma.fetch('run_samples', 1),
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
          - Goal: all models must satisfy `competitor_response_p95 / gte_response_p95 >= 1.0` for every enabled competitor.
          - Regression: compare against previous run; fail if GTE response-time p95 increases by more than 15%.
          - Primary workload: in-process thread pool with concurrency `16`.
        MD
      end

      goal_status = entry.dig('status', 'goal_response_p95_ratio_all_models') ? 'PASS' : 'FAIL'
      regression_status = entry.dig('status', 'regression_vs_previous') ? 'PASS' : 'FAIL'

      File.open(runs_path, 'a') do |file|
        file.puts
        file.puts "## #{entry.fetch('generated_at')} | v#{entry.fetch('gem_version')} | #{entry.fetch('git_sha')}"
        file.puts "- Goal (response-time p95 ratio across enabled competitors): #{goal_status}"
        file.puts "- Regression vs previous run (GTE response-time p95 <= +#{(entry.dig('thresholds', 'regression_tolerance') * 100).round(1)}%): #{regression_status}"
        file.puts
        file.puts '```json'
        file.puts JSON.pretty_generate(entry)
        file.puts '```'
      end
    end

    def current_version
      File.read(File.expand_path('../VERSION', __dir__)).strip
    end

    def check_entry!(entry, goal_only: false)
      failures = []
      unless entry.dig('status', 'goal_response_p95_ratio_all_models')
        failures << 'goal failure: one or more models lost the response-time p95 comparison'
      end

      unless goal_only || entry.dig('status', 'regression_vs_previous')
        failures << 'regression failure: one or more models regressed above allowed response-time p95 tolerance'
      end

      failures
    end

    def latest_result_path
      Dir.glob(File.expand_path('results/puma_compare_*.json', __dir__)).max
    end

    def run_cli(argv)
      command = argv.shift
      case command
      when 'append'
        options = { runs: DEFAULT_RUNS_PATH, tolerance: DEFAULT_TOLERANCE, result: nil }
        OptionParser.new do |opts|
          opts.on('--result PATH') { |value| options[:result] = File.expand_path(value, ROOT) }
          opts.on('--runs PATH') { |value| options[:runs] = File.expand_path(value, ROOT) }
          opts.on('--max-regression FLOAT', Float) { |value| options[:tolerance] = value }
          opts.on('--latest') { options[:result] = latest_result_path }
        end.parse!(argv)

        raise LedgerError, '--result PATH or --latest is required' unless options[:result]

        result = load_result(options[:result])
        entries = load_entries(options[:runs])
        if duplicate_entry?(entries, result)
          puts "Run already recorded in #{Pathname.new(options[:runs]).relative_path_from(Pathname.new(ROOT))}"
          return 0
        end

        previous = previous_entry(entries, result)
        entry = build_entry(result, previous: previous, tolerance: options[:tolerance])
        append_entry(options[:runs], entry)
        puts "Appended run to #{Pathname.new(options[:runs]).relative_path_from(Pathname.new(ROOT))}"
        puts "goal=#{entry.dig('status', 'goal_response_p95_ratio_all_models') ? 'PASS' : 'FAIL'} regression=#{entry.dig('status', 'regression_vs_previous') ? 'PASS' : 'FAIL'}"
        0
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
        end.parse!(argv)

        raise LedgerError, '--result PATH or --latest is required' unless options[:result]

        result = load_result(options[:result])
        entries = options[:goal_only] ? [] : load_entries(options[:runs])
        previous = options[:goal_only] ? nil : previous_entry(entries, result)
        entry = build_entry(result, previous: previous, tolerance: options[:tolerance])
        failures = check_entry!(entry, goal_only: options[:goal_only])

        if options[:require_current_version]
          versions = load_entries(options[:runs]).map { |ledger_entry| ledger_entry['gem_version'] }.uniq
          unless versions.include?(current_version)
            failures << "current gem version #{current_version} is not recorded in RUNS.md"
          end
        end

        if failures.empty?
          puts 'PASS'
          0
        else
          failures.each { |failure| warn failure }
          1
        end
      when 'verify-current-version'
        entries = load_entries(DEFAULT_RUNS_PATH)
        if entries.any? { |entry| entry['gem_version'] == current_version }
          puts "PASS: current version #{current_version} exists in RUNS.md"
          0
        else
          warn "FAIL: current version #{current_version} missing from RUNS.md"
          1
        end
      else
        warn <<~USAGE
          Usage:
            ruby bench/runs_ledger.rb append --result PATH [--runs RUNS.md] [--max-regression 0.05]
            ruby bench/runs_ledger.rb append --latest [--runs RUNS.md]
            ruby bench/runs_ledger.rb check --result PATH [--runs RUNS.md] [--max-regression 0.05]
            ruby bench/runs_ledger.rb check --latest [--runs RUNS.md]
            ruby bench/runs_ledger.rb verify-current-version
        USAGE
        1
      end
    end
  end
  # rubocop:enable Metrics/ModuleLength
end
