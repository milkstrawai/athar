# frozen_string_literal: true

require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_record/railtie"
require "active_job/railtie"
require "action_controller/railtie"

Bundler.require(*Rails.groups)
require "fx"
require "athar"

module Dummy
  class Application < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f
    config.eager_load = false
    config.root = File.expand_path("..", __dir__)

    config.active_record.schema_format = if ENV["ATHAR_NO_FX"] == "1"
                                           :sql
                                         else
                                           :ruby
                                         end

    config.active_record.dump_schema_after_migration = false
    config.active_job.queue_adapter = :test
    config.logger = Logger.new(File::NULL)
  end
end
