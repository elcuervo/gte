# frozen_string_literal: true

require 'spec_helper'
require_relative '../../bench/harness'

RSpec.describe Bench::MultiRuntimeHarness do
  class FakeAdapter
    attr_reader :name, :profile

    # rubocop:disable Metrics/ParameterLists
    def initialize(name:, delay:, vectors:, required: false, available: true, reason: nil)
      @name = name
      @delay = delay
      @vectors = vectors
      @required = required
      @available = available
      @reason = reason
      @profile = {}
    end
    # rubocop:enable Metrics/ParameterLists

    def available?
      @available
    end

    def unavailable_reason
      @reason
    end

    def required?
      @required
    end

    def supports_model?(_model_key)
      true
    end

    def build(_model_dir, _profile)
      FakeInstance.new(delay: @delay, vectors: @vectors)
    end
  end

  class FakeInstance
    def initialize(delay:, vectors:)
      @delay = delay
      @vectors = vectors
    end

    def embed(text_or_batch)
      sleep(@delay)
      Array(text_or_batch).map { |text| @vectors.fetch(text, [1.0, 0.0]) }
    end
  end

  let(:model_catalog) do
    {
      'demo' => {
        'label' => 'Demo model',
        'dir' => '/tmp/demo-model',
        'probe_texts' => %w[probe-a probe-b],
        'request_template' => 'request-%<idx>s'
      }
    }
  end

  let(:gte_vectors) do
    {
      'probe-a' => [1.0, 0.0],
      'probe-b' => [0.0, 1.0],
      'request-0' => [1.0, 0.0],
      'request-1' => [0.0, 1.0],
      'benchmark text 0 for demo' => [1.0, 0.0],
      'benchmark text 1 for demo' => [0.0, 1.0]
    }
  end

  # rubocop:disable Metrics/MethodLength
  def build_harness(adapters:, scenarios: ['puma_like_single_request'])
    described_class.new(
      models: model_catalog,
      adapters: adapters,
      scenarios: scenarios,
      thresholds: {
        'max_abs' => 1e-5,
        'min_cos' => 0.99999,
        'min_p95_ratio' => 1.0
      },
      puma: {
        'iterations' => 2,
        'concurrency' => 1,
        'run_samples' => 1
      },
      batch: {
        'iterations' => 2,
        'batch_sizes' => [1, 2]
      }
    )
  end
  # rubocop:enable Metrics/MethodLength

  it 'skips unavailable optional adapters and keeps the remaining goal comparison' do
    harness = build_harness(
      adapters: [
        FakeAdapter.new(name: 'gte', delay: 0.002, vectors: gte_vectors, required: true),
        FakeAdapter.new(name: 'pure_ruby', delay: 0.004, vectors: gte_vectors, required: true),
        FakeAdapter.new(
          name: 'python_onnxruntime',
          delay: 0.001,
          vectors: gte_vectors,
          available: false,
          reason: 'python runtime unavailable'
        )
      ]
    )

    result = harness.run

    expect(result.payload.dig('adapters', 'python_onnxruntime', 'status')).to eq('skipped')
    expect(result.payload.dig('models', 'demo', 'adapters', 'python_onnxruntime', 'status')).to eq('skipped')
    expect(result.goal_failures).to be_empty
  end

  it 'fails the p95 gate when a competitor is faster than gte' do
    harness = build_harness(
      adapters: [
        FakeAdapter.new(name: 'gte', delay: 0.004, vectors: gte_vectors, required: true),
        FakeAdapter.new(name: 'pure_ruby', delay: 0.001, vectors: gte_vectors, required: true)
      ]
    )

    result = harness.run

    expect(result.goal_failures).not_to be_empty
    expect(result.payload.dig('models', 'demo', 'scenarios', 'puma_like_single_request', 'gate', 'pass')).to be(false)
  end

  it 'emits the shared multi-scenario result schema' do
    harness = build_harness(
      adapters: [
        FakeAdapter.new(name: 'gte', delay: 0.001, vectors: gte_vectors, required: true),
        FakeAdapter.new(name: 'pure_ruby', delay: 0.002, vectors: gte_vectors, required: true)
      ],
      scenarios: %w[puma_like_single_request batch_amortization]
    )

    result = harness.run

    expect(result.payload.fetch('version')).to eq(3)
    expect(result.payload.fetch('kind')).to eq('multi_runtime_benchmark')
    expect(result.payload.dig('models', 'demo', 'correctness', 'comparisons', 'pure_ruby', 'pass')).to be(true)
    expect(result.payload.dig('models', 'demo', 'scenarios', 'batch_amortization', 'batches', 'batch_1')).to be_a(Hash)
    expect(
      result.payload.dig('models', 'demo', 'scenarios', 'puma_like_single_request', 'by_adapter', 'gte')
    ).to be_a(Hash)
  end
end
