#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require 'pathname'
require 'time'

require 'gte'
require_relative 'pure_ruby_runtime'

module Bench
  class HarnessError < StandardError; end

  RunResult = Struct.new(:payload, :correctness_failures, :goal_failures, keyword_init: true)

  class MultiRuntimeHarness
    ROOT = File.expand_path('..', __dir__)
    DEFAULT_OUTPUT_DIR = File.expand_path('results', __dir__)
    DEFAULT_BATCH_SIZES = [1, 8, 32, 128].freeze

    MODELS = {
      'e5' => {
        'label' => 'E5 multilingual small',
        'env_var' => 'GTE_MODEL_DIR',
        'probe_texts' => [
          'query: benchmark validation probe',
          'query: machine learning basics',
          'passage: gradient descent updates model parameters'
        ],
        'request_template' => 'query: puma request %{idx} for e5'
      },
      'clip' => {
        'label' => 'CLIP ViT-B/32 text encoder',
        'env_var' => 'GTE_CLIP_DIR',
        'probe_texts' => [
          'a photo of a cat',
          'a picture of a kitten',
          'a blueprint of a skyscraper'
        ],
        'request_template' => 'a text prompt %{idx} for clip'
      },
      'siglip2' => {
        'label' => 'Siglip2 base text encoder',
        'env_var' => 'GTE_SIGLIP2_DIR',
        'probe_texts' => [
          'a photo of a cat',
          'a photo of a dog',
          'a geometric abstract logo'
        ],
        'request_template' => 'a text prompt %{idx} for siglip2'
      }
    }.freeze

    def self.default_output_path(prefix)
      timestamp = Time.now.utc.strftime('%Y%m%dT%H%M%SZ')
      File.join(DEFAULT_OUTPUT_DIR, "#{prefix}_#{timestamp}.json")
    end

    def self.resolve_models(root: ROOT, catalog: MODELS)
      catalog.each_with_object({}) do |(key, cfg), out|
        dir = ENV.fetch(cfg.fetch('env_var'), nil)
        next if dir.nil? || dir.empty?

        expanded = File.expand_path(dir, root)
        next unless Dir.exist?(expanded)

        out[key] = cfg.merge('dir' => expanded)
      end
    end

    def self.write_payload(path, payload)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "#{JSON.pretty_generate(payload)}\n")
    end

    # rubocop:disable Metrics/ParameterLists
    def initialize(models:, adapters:, scenarios:, thresholds:, puma: nil, batch: nil, root: ROOT)
      @models = models
      @adapters = adapters
      @scenarios = scenarios
      @thresholds = thresholds
      @puma_options = puma
      @batch_options = batch
      @root = root
    end
    # rubocop:enable Metrics/ParameterLists

    def run
      payload = {
        'version' => 3,
        'kind' => 'multi_runtime_benchmark',
        'generated_at' => Time.now.utc.iso8601,
        'ruby_version' => RUBY_VERSION,
        'platform' => RUBY_PLATFORM,
        'gem_version' => File.read(File.expand_path('VERSION', @root)).strip,
        'git_sha' => `git -C #{@root} rev-parse --short HEAD`.strip,
        'scenarios' => @scenarios,
        'thresholds' => @thresholds.merge(
          'goal_metric' => 'response_time_p95_and_service_time_p95',
          'sample_aggregation' => 'median'
        ),
        'adapters' => adapter_metadata,
        'models' => {},
        'summary' => {
          'correctness_pass' => true,
          'goal_pass' => true,
          'correctness_failures' => [],
          'goal_failures' => []
        }
      }

      correctness_failures = []
      goal_failures = []

      @models.each do |key, cfg|
        model_payload, model_correctness_failures, model_goal_failures = run_model(key, cfg)
        payload.fetch('models')[key] = model_payload
        correctness_failures.concat(model_correctness_failures)
        goal_failures.concat(model_goal_failures)
      end

      payload.fetch('summary')['correctness_pass'] = correctness_failures.empty?
      payload.fetch('summary')['goal_pass'] = goal_failures.empty?
      payload.fetch('summary')['correctness_failures'] = correctness_failures
      payload.fetch('summary')['goal_failures'] = goal_failures

      RunResult.new(
        payload: payload,
        correctness_failures: correctness_failures,
        goal_failures: goal_failures
      )
    end

    private

    def adapter_metadata
      @adapters.each_with_object({}) do |adapter, out|
        available = adapter.available?
        out[adapter.name] = {
          'required' => adapter.required?,
          'available' => available,
          'status' => available ? 'available' : 'skipped',
          'reason' => available ? nil : adapter.unavailable_reason,
          'profile' => adapter.profile
        }.compact
      end
    end

    def run_model(key, cfg)
      puts "\n#{cfg.fetch('label')} (#{key})"
      puts "  dir: #{Pathname.new(cfg.fetch('dir')).relative_path_from(Pathname.new(@root))}"

      instances = {}
      model_payload = {
        'label' => cfg.fetch('label'),
        'dir' => Pathname.new(cfg.fetch('dir')).relative_path_from(Pathname.new(@root)).to_s,
        'adapters' => {},
        'correctness' => {},
        'scenarios' => {}
      }

      @adapters.each do |adapter|
        unless adapter.available?
          model_payload.fetch('adapters')[adapter.name] = {
            'status' => 'skipped',
            'reason' => adapter.unavailable_reason
          }
          next
        end

        unless adapter.supports_model?(key)
          model_payload.fetch('adapters')[adapter.name] = {
            'status' => 'skipped',
            'reason' => "adapter does not support model '#{key}'"
          }
          next
        end

        instances[adapter.name] = adapter.build(cfg.fetch('dir'), adapter.profile)
        model_payload.fetch('adapters')[adapter.name] = { 'status' => 'ready' }
      rescue StandardError => e
        raise if adapter.required?

        model_payload.fetch('adapters')[adapter.name] = {
          'status' => 'skipped',
          'reason' => e.message
        }
      end

      raise HarnessError, "gte adapter unavailable for #{key}" unless instances.key?('gte')

      begin
        correctness_failures = run_correctness(cfg, instances, model_payload)
        goal_failures = []

        if @scenarios.include?('puma_like_single_request')
          scenario_payload, scenario_failures = run_puma_scenario(cfg, instances)
          model_payload.fetch('scenarios')['puma_like_single_request'] = scenario_payload
          goal_failures.concat(scenario_failures)
        end

        if @scenarios.include?('batch_amortization')
          model_payload.fetch('scenarios')['batch_amortization'] = run_batch_scenario(key, instances)
        end

        [model_payload, correctness_failures, goal_failures]
      ensure
        instances.each_value do |instance|
          instance.close if instance.respond_to?(:close)
        end
      end
    end

    def run_correctness(cfg, instances, model_payload)
      probe_texts = cfg.fetch('probe_texts')
      gte_embeddings = materialize_embeddings(instances.fetch('gte').embed(probe_texts))
      dim = gte_embeddings.first&.length || 0
      puts format('  gte reference: rows=%<rows>d dim=%<dim>d', rows: probe_texts.length, dim: dim)

      comparisons = {}
      failures = []

      instances.each do |name, instance|
        next if name == 'gte'

        embeddings = materialize_embeddings(instance.embed(probe_texts))
        comparison = compare_embeddings(embeddings, gte_embeddings)
        comparison['pass'] =
          comparison.fetch('max_abs') <= @thresholds.fetch('max_abs') &&
          comparison.fetch('min_cosine') >= @thresholds.fetch('min_cos')
        comparisons[name] = comparison

        puts format('  correctness %<name>-18s max_abs=%<max>.9f mean_abs=%<mean>.9f min_cosine=%<cos>.9f',
                    name: name,
                    max: comparison.fetch('max_abs'),
                    mean: comparison.fetch('mean_abs'),
                    cos: comparison.fetch('min_cosine'))

        next if comparison.fetch('pass')

        failures << "#{cfg.fetch('label')} #{name} failed correctness thresholds"
      end

      model_payload['correctness'] = {
        'rows' => probe_texts.length,
        'dim' => dim,
        'comparisons' => comparisons
      }
      failures
    end

    def run_puma_scenario(cfg, instances)
      warmup_requests = Array.new(@puma_options.fetch('concurrency')) do
        format(cfg.fetch('request_template'), idx: 'warmup')
      end
      requests = generate_requests(cfg.fetch('request_template'), @puma_options.fetch('iterations'))

      puts '  puma-like benchmark:'
      instances.each_value { |instance| benchmark_concurrent(instance, warmup_requests, @puma_options.fetch('concurrency')) }

      by_adapter = benchmark_puma_samples(instances, requests)
      gate = puma_gate(by_adapter)
      print_puma_summary(by_adapter, gate)

      [
        {
          'iterations' => @puma_options.fetch('iterations'),
          'concurrency' => @puma_options.fetch('concurrency'),
          'run_samples' => @puma_options.fetch('run_samples'),
          'by_adapter' => by_adapter,
          'gate' => gate
        },
        gate.fetch('pass') ? [] : gate.fetch('failures')
      ]
    end

    def run_batch_scenario(key, instances)
      puts '  batch amortization:'
      batches = {}

      @batch_options.fetch('batch_sizes').each do |size|
        texts = Array.new(size) { |index| "benchmark text #{index} for #{key}" }
        summaries = benchmark_batch_iterations(instances, texts, @batch_options.fetch('iterations'))
        comparisons = competitor_ratios(summaries, %w[median_ms], 'median_ms', 1.0)

        puts format('    batch=%<size>3d %<summary>s',
                    size: size,
                    summary: summaries.map do |name, stats|
                      format('%<name>s=%<median>.2fms', name: name, median: stats.fetch('median_ms'))
                    end.join(' '))

        batches["batch_#{size}"] = {
          'by_adapter' => summaries,
          'comparisons' => comparisons
        }
      end

      {
        'iterations' => @batch_options.fetch('iterations'),
        'batch_sizes' => @batch_options.fetch('batch_sizes'),
        'batches' => batches
      }
    end

    def benchmark_puma_samples(instances, requests)
      samples = instances.keys.to_h { |name| [name, []] }

      @puma_options.fetch('run_samples').times do |sample_index|
        instances.keys.rotate(sample_index).each do |name|
          samples.fetch(name) << benchmark_concurrent(
            instances.fetch(name),
            requests,
            @puma_options.fetch('concurrency')
          )
        end
      end

      samples.transform_values do |adapter_samples|
        {
          'samples' => adapter_samples,
          'aggregate' => aggregate_concurrent_samples(adapter_samples)
        }
      end
    end

    def benchmark_batch_iterations(instances, texts, iterations)
      timings = instances.keys.to_h { |name| [name, []] }
      instances.each_value { |instance| instance.embed(texts) }

      iterations.times do |iteration_index|
        instances.keys.rotate(iteration_index).each do |name|
          started_at = monotonic_time
          instances.fetch(name).embed(texts)
          timings.fetch(name) << elapsed_ms(started_at)
        end
      end

      timings.transform_values do |samples|
        summary = latency_summary(samples)
        summary['per_item_ms'] = summary.fetch('median_ms') / texts.length
        summary
      end
    end

    def benchmark_concurrent(instance, request_texts, concurrency)
      queue = Queue.new
      dispatch_time = monotonic_time
      request_texts.each_with_index { |text, index| queue << [index, text, dispatch_time] }

      service_latencies = Array.new(request_texts.length)
      response_latencies = Array.new(request_texts.length)
      errors = Queue.new
      mutex = Mutex.new

      started_at = monotonic_time
      workers = Array.new(concurrency) do
        Thread.new do
          loop do
            index, text, enqueued_at = queue.pop(true)
            service_started_at = monotonic_time
            instance.embed(text)
            finished_at = monotonic_time

            mutex.synchronize do
              service_latencies[index] = milliseconds_between(service_started_at, finished_at)
              response_latencies[index] = milliseconds_between(enqueued_at, finished_at)
            end
          rescue ThreadError
            break
          rescue StandardError => e
            errors << e
            break
          end
        end
      end
      workers.each(&:join)
      raise errors.pop unless errors.empty?

      wall_ms = elapsed_ms(started_at)
      {
        'response_time' => latency_summary(response_latencies),
        'service_time' => latency_summary(service_latencies),
        'requests' => request_texts.length,
        'wall_ms' => wall_ms,
        'throughput_rps' => request_texts.length / (wall_ms / 1000.0)
      }
    end

    def puma_gate(by_adapter)
      response = metric_gate(
        by_adapter: by_adapter,
        metric_path: %w[aggregate response_time p95_ms],
        metric_label: 'response_time.p95_ms',
        threshold: @thresholds.fetch('min_p95_ratio')
      )
      service = metric_gate(
        by_adapter: by_adapter,
        metric_path: %w[aggregate service_time p95_ms],
        metric_label: 'service_time.p95_ms',
        threshold: @thresholds.fetch('min_service_ratio', 1.0)
      )
      failures = response.fetch('failures') + service.fetch('failures')
      {
        'response' => response,
        'service' => service,
        'pass' => failures.empty?,
        'failures' => failures
      }
    end

    def print_puma_summary(by_adapter, gate)
      by_adapter.each do |name, payload|
        aggregate = payload.fetch('aggregate')
        puts format('    %<name>-18s response_p95=%<rp95>.2fms service_p95=%<sp95>.2fms throughput=%<rps>.2frps',
                    name: name,
                    rp95: aggregate.fetch('response_time').fetch('p95_ms'),
                    sp95: aggregate.fetch('service_time').fetch('p95_ms'),
                    rps: aggregate.fetch('throughput_rps'))
      end

      gate.fetch('response').fetch('comparisons').each do |name, comparison|
        puts format('    ratio %<name>-12s %<metric>s=%<ratio>.2fx (%<status>s)',
                    name: name,
                    metric: comparison.fetch('metric'),
                    ratio: comparison.fetch('ratio_over_gte'),
                    status: comparison.fetch('pass') ? 'PASS' : 'FAIL')
      end
      gate.fetch('service').fetch('comparisons').each do |name, comparison|
        puts format('    ratio %<name>-12s %<metric>s=%<ratio>.2fx (%<status>s)',
                    name: name,
                    metric: comparison.fetch('metric'),
                    ratio: comparison.fetch('ratio_over_gte'),
                    status: comparison.fetch('pass') ? 'PASS' : 'FAIL')
      end
    end

    def metric_gate(by_adapter:, metric_path:, metric_label:, threshold:)
      comparisons = competitor_ratios(by_adapter, metric_path, metric_label, threshold)
      failures = comparisons.each_with_object([]) do |(name, comparison), out|
        next if comparison.fetch('pass')

        out << "#{name} #{metric_label} ratio #{comparison.fetch('ratio_over_gte').round(2)}x < #{threshold}x"
      end
      {
        'metric' => metric_label,
        'threshold_ratio' => threshold,
        'minimum_ratio_over_gte' => comparisons.values.map { |comparison| comparison.fetch('ratio_over_gte') }.min,
        'comparisons' => comparisons,
        'failures' => failures
      }
    end

    def competitor_ratios(results_by_adapter, metric_path, metric_label, threshold)
      gte_metric = dig_metric(results_by_adapter.fetch('gte'), metric_path)

      results_by_adapter.each_with_object({}) do |(name, payload), out|
        next if name == 'gte'

        competitor_metric = dig_metric(payload, metric_path)
        ratio = competitor_metric / gte_metric
        out[name] = {
          'metric' => metric_label,
          'gte_value' => gte_metric,
          'competitor_value' => competitor_metric,
          'ratio_over_gte' => ratio,
          'pass' => ratio >= threshold
        }
      end
    end

    def dig_metric(payload, path)
      path.reduce(payload) { |memo, key| memo.fetch(key) }
    end

    def aggregate_concurrent_samples(samples)
      {
        'response_time' => aggregate_metric_group(samples, 'response_time'),
        'service_time' => aggregate_metric_group(samples, 'service_time'),
        'throughput_rps' => metric_median(samples, ['throughput_rps']),
        'requests' => metric_median(samples, ['requests'])
      }
    end

    def aggregate_metric_group(samples, key)
      {
        'median_ms' => metric_median(samples, [key, 'median_ms']),
        'p95_ms' => metric_median(samples, [key, 'p95_ms']),
        'p99_ms' => metric_median(samples, [key, 'p99_ms']),
        'min_ms' => metric_median(samples, [key, 'min_ms']),
        'max_ms' => metric_median(samples, [key, 'max_ms'])
      }
    end

    def metric_median(samples, path)
      values = samples.map { |sample| path.reduce(sample) { |memo, key| memo.fetch(key) } }
      values.sort[values.length / 2]
    end

    def generate_requests(template, iterations)
      Array.new(iterations) { |index| format(template, idx: index) }
    end

    def compare_embeddings(actual, reference)
      if actual.length != reference.length
        raise HarnessError, "row count mismatch: #{actual.length} vs #{reference.length}"
      end

      max_abs = 0.0
      mean_abs = 0.0
      min_cosine = Float::INFINITY
      count = 0

      actual.zip(reference).each do |actual_row, reference_row|
        if actual_row.length != reference_row.length
          raise HarnessError, "dimension mismatch: #{actual_row.length} vs #{reference_row.length}"
        end

        actual_row.zip(reference_row).each do |actual_value, reference_value|
          diff = (actual_value - reference_value).abs
          max_abs = diff if diff > max_abs
          mean_abs += diff
          count += 1
        end

        cosine = cosine_similarity(actual_row, reference_row)
        min_cosine = cosine if cosine < min_cosine
      end

      {
        'max_abs' => max_abs,
        'mean_abs' => count.zero? ? 0.0 : mean_abs / count,
        'min_cosine' => min_cosine
      }
    end

    def cosine_similarity(left, right)
      dot = left.zip(right).sum { |a, b| a * b }
      norm_left = Math.sqrt(left.sum { |value| value * value })
      norm_right = Math.sqrt(right.sum { |value| value * value })
      return 0.0 if norm_left.zero? || norm_right.zero?

      dot / (norm_left * norm_right)
    end

    def materialize_embeddings(result)
      return result if result.is_a?(Array)
      return result.to_a if result.respond_to?(:to_a)

      result
    end

    def latency_summary(samples_ms)
      sorted = samples_ms.compact.sort
      {
        'median_ms' => sorted[sorted.length / 2],
        'p95_ms' => percentile(sorted, 0.95),
        'p99_ms' => percentile(sorted, 0.99),
        'min_ms' => sorted.first,
        'max_ms' => sorted.last
      }
    end

    def percentile(sorted, percentile_value)
      index = (sorted.length * percentile_value).floor
      index = sorted.length - 1 if index >= sorted.length
      sorted[index]
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def elapsed_ms(started_at)
      milliseconds_between(started_at, monotonic_time)
    end

    def milliseconds_between(started_at, finished_at)
      (finished_at - started_at) * 1000.0
    end
  end

  module Adapters
    class Gte
      attr_reader :profile

      def initialize(profile: { 'execution_providers' => 'cpu' })
        @profile = profile
      end

      def name
        'gte'
      end

      def available?
        true
      end

      def unavailable_reason
        nil
      end

      def required?
        true
      end

      def supports_model?(_model_key)
        true
      end

      def build(model_dir, profile_override = profile)
        model = GTE.config(model_dir) do |config|
          config.with(
            execution_providers: profile_override.fetch('execution_providers', 'cpu')
          )
        end
        StaticInstance.new(model)
      end
    end

    class PureRuby
      attr_reader :profile

      def initialize(profile: {})
        @profile = profile
      end

      def name
        'pure_ruby'
      end

      def available?
        true
      end

      def unavailable_reason
        nil
      end

      def required?
        true
      end

      def supports_model?(_model_key)
        true
      end

      def build(model_dir, _profile_override = profile)
        StaticInstance.new(PureRubyTextEmbedding::TextEncoder.new(model_dir: model_dir))
      end
    end

    class PythonOnnxRuntime
      SCRIPT_PATH = File.expand_path('python_onnxruntime.py', __dir__)

      attr_reader :profile

      def initialize(profile: { 'worker_pool' => 1, 'intra_threads' => 1, 'inter_threads' => 1 })
        @profile = profile
      end

      def name
        'python_onnxruntime'
      end

      def available?
        availability.fetch('available')
      end

      def unavailable_reason
        availability['reason']
      end

      def required?
        false
      end

      def supports_model?(_model_key)
        true
      end

      def build(model_dir, profile_override = profile)
        PythonInstance.new(model_dir: model_dir, profile: profile_override, python_command: python_command)
      end

      private

      def availability
        @availability ||= begin
          stdout, stderr, status = Open3.capture3(python_command, SCRIPT_PATH, '--check')
          if status.success?
            { 'available' => true, 'details' => stdout.strip }
          else
            { 'available' => false, 'reason' => [stderr, stdout].map(&:strip).reject(&:empty?).join(' | ') }
          end
        rescue Errno::ENOENT => e
          { 'available' => false, 'reason' => e.message }
        end
      end

      def python_command
        ENV.fetch('PYTHON', 'python3')
      end
    end

    class StaticInstance
      def initialize(backend)
        @backend = backend
      end

      def embed(text_or_batch)
        @backend.embed(text_or_batch)
      end
    end

    class PythonInstance
      def initialize(model_dir:, profile:, python_command:)
        @workers = Array.new(profile.fetch('worker_pool', 1)) do
          PythonWorker.new(model_dir: model_dir, profile: profile, python_command: python_command)
        end
        @available = Queue.new
        @workers.each { |worker| @available << worker }
      end

      def embed(text_or_batch)
        worker = @available.pop
        texts = text_or_batch.is_a?(Array) ? text_or_batch : [text_or_batch]
        worker.embed(texts)
      ensure
        @available << worker if worker
      end

      def close
        @workers.each(&:close)
      end
    end

    class PythonWorker
      def initialize(model_dir:, profile:, python_command:)
        env = {
          'OMP_NUM_THREADS' => profile.fetch('intra_threads', 1).to_s,
          'OMP_WAIT_POLICY' => 'PASSIVE'
        }
        @stdin, @stdout, @stderr, @wait_thread = Open3.popen3(
          env,
          python_command,
          PythonOnnxRuntime::SCRIPT_PATH,
          '--serve',
          '--model-dir',
          model_dir,
          '--profile',
          JSON.generate(profile)
        )
      end

      def embed(texts)
        @stdin.puts(JSON.generate({ 'action' => 'embed', 'texts' => texts }))
        @stdin.flush

        line = @stdout.gets
        raise HarnessError, 'python adapter exited before returning output' if line.nil?

        response = JSON.parse(line)
        raise HarnessError, response.fetch('error') if response['error']

        response.fetch('embeddings')
      end

      def close
        @stdin.close unless @stdin.closed?
        @stdout.close unless @stdout.closed?
        @stderr.close unless @stderr.closed?
        Process.kill('TERM', @wait_thread.pid) if @wait_thread.alive?
      rescue Errno::ESRCH, IOError
        nil
      ensure
        @wait_thread&.join(0.2)
      end
    end
  end
end
