# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require_relative '../../bench/ledger'

RSpec.describe Bench::RunsLedger do
  # rubocop:disable Metrics/MethodLength
  def sample_result(min_ratio: 1.2)
    model_payload = {
      'scenarios' => {
        'puma_like_single_request' => {
          'by_adapter' => {
            'gte' => {
              'aggregate' => {
                'response_time' => { 'p95_ms' => 10.0, 'median_ms' => 8.0 },
                'service_time' => { 'p95_ms' => 9.0 },
                'throughput_rps' => 100.0
              }
            }
          },
          'gate' => {
            'minimum_ratio_over_gte' => min_ratio,
            'comparisons' => {
              'pure_ruby' => {
                'metric' => 'response_time.p95_ms',
                'gte_value' => 10.0,
                'competitor_value' => 12.0,
                'ratio_over_gte' => min_ratio,
                'pass' => min_ratio >= 1.0
              }
            }
          }
        }
      }
    }

    {
      'generated_at' => Time.now.utc.iso8601,
      'gem_version' => '0.0.7',
      'git_sha' => 'abc123',
      'platform' => RUBY_PLATFORM,
      'ruby_version' => RUBY_VERSION,
      'thresholds' => {
        'min_p95_ratio' => 1.0,
        'sample_aggregation' => 'median'
      },
      'puma_like' => {
        'concurrency' => 16,
        'iterations' => 40,
        'run_samples' => 3
      },
      'models' => {
        'e5' => Marshal.load(Marshal.dump(model_payload)),
        'clip' => Marshal.load(Marshal.dump(model_payload)),
        'siglip2' => Marshal.load(Marshal.dump(model_payload))
      }
    }
  end
  # rubocop:enable Metrics/MethodLength

  it 'builds ledger entries from the multi-runtime benchmark schema' do
    entry = described_class.build_entry(sample_result, previous: nil, tolerance: 0.15)

    expect(entry.dig('status', 'goal_response_p95_ratio_all_models')).to be(true)
    expect(entry.dig('metrics', 'e5', 'minimum_ratio_p95')).to eq(1.2)
  end

  it 'appends and reloads entries from RUNS.md' do
    entry = described_class.build_entry(sample_result, previous: nil, tolerance: 0.15)

    Dir.mktmpdir do |dir|
      runs_path = File.join(dir, 'RUNS.md')
      described_class.append_entry(runs_path, entry)

      entries = described_class.load_entries(runs_path)
      expect(entries.length).to eq(1)
      expect(entries.first.fetch('kind')).to eq('puma_compare_run')
    end
  end
end
