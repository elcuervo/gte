require_relative "boot"

require "rails"
require "action_controller/railtie"

Bundler.require(*Rails.groups)

module Embench
  class Application < Rails::Application
    config.load_defaults 7.1
    config.api_only = true
    config.eager_load = true
    config.log_level = :warn
    config.logger = Logger.new($stdout)
    config.logger.formatter = ->(_, _, _, msg) { "#{msg}\n" }
  end
end
