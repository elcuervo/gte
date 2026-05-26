# frozen_string_literal: true

workers    ENV.fetch('WEB_CONCURRENCY', 0).to_i
threads    ENV.fetch('MIN_THREADS', 2).to_i, ENV.fetch('MAX_THREADS', 5).to_i
preload_app!
bind 'tcp://0.0.0.0:3000'
quiet
