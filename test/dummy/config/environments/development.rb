# frozen_string_literal: true

Rails.application.configure do
  config.cache_classes = false
  config.eager_load = false
  config.consider_all_requests_local = true
  config.action_controller.perform_caching = false if defined?(ActionController::Base)
  config.action_dispatch.show_exceptions = :all if defined?(ActionDispatch)
  config.active_support.deprecation = :log
  config.logger = ActiveSupport::Logger.new($stdout)
  config.log_level = :info
  config.assets.debug = true if config.respond_to?(:assets)
  config.action_controller.allow_forgery_protection = false if defined?(ActionController::Base)
end
