# frozen_string_literal: true

require "active_support"
require "active_support/core_ext/numeric/time"
require "active_support/core_ext/string/inflections"
require "active_support/json"
require "active_record"
require "active_job"
require "fx"

require_relative "athar/version"
require_relative "athar/configuration"
require_relative "athar/sql"
require_relative "athar/metadata_stack"
require_relative "athar/context"
require_relative "athar/deletion"
require_relative "athar/table_event"
require_relative "athar/retention"
require_relative "athar/dashboard"

module Athar
  class Error < StandardError; end

  class ConfigurationError < Error; end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def reset_configuration!
      @configuration = Configuration.new
    end

    def logger
      configuration.logger || (Rails.logger if defined?(Rails)) || Logger.new($stdout)
    end

    def with_actor(...)
      Context.with_actor(...)
    end

    def with_metadata(...)
      Context.with_metadata(...)
    end

    def with_context(...)
      Context.with_context(...)
    end

    def without_capture(...)
      Context.without_capture(...)
    end
  end
end

require_relative "athar/retention_job" if defined?(ActiveJob)
require_relative "athar/engine" if defined?(Rails::Engine)
