# frozen_string_literal: true

Rails.application.configure do
  config.cache_classes = true
  config.eager_load = false
  config.consider_all_requests_local = true
  config.action_controller.perform_caching = false if defined?(ActionController::Base)
  config.action_dispatch.show_exceptions = false if defined?(ActionDispatch)
  config.active_support.deprecation = :stderr
end
