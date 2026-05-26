# frozen_string_literal: true

require 'active_support/core_ext/integer/time'

Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.log_level = :warn
end

Rails.application.config.secret_key_base = ENV.fetch('SECRET_KEY_BASE', 'b' * 128)
