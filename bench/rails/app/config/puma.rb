# frozen_string_literal: true

workers_count = ENV.key?('WEB_CONCURRENCY') ? ENV.fetch('WEB_CONCURRENCY').to_i : :auto
threads_min = Integer(ENV.fetch('MIN_THREADS', 2))
threads_max = Integer(ENV.fetch('MAX_THREADS', 5))

workers workers_count
threads threads_min, threads_max

preload_app!
bind 'tcp://0.0.0.0:3000'

worker_timeout Integer(ENV.fetch('WORKER_TIMEOUT', 60))

on_worker_boot do
  GteRuntime.warmup! if defined?(GteRuntime)
end

silence_single_worker_warning
quiet
