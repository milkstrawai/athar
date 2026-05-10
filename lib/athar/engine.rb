# frozen_string_literal: true

require_relative "middleware/asset_server"

module Athar
  class Engine < ::Rails::Engine
    isolate_namespace Athar

    initializer "athar.set_logger" do
      Athar.configuration.logger ||= Rails.logger
    end

    initializer "athar.middleware" do |app|
      app.middleware.use MetadataStackMiddleware
    end

    initializer "athar.assets" do |app|
      if app.config.respond_to?(:assets)
        app.config.assets.paths << root.join("app/assets/stylesheets").to_s
        app.config.assets.paths << root.join("app/assets/javascripts").to_s
        app.config.assets.paths << root.join("app/assets/images").to_s

        if defined?(::Sprockets)
          app.config.assets.precompile += %w[athar/dashboard.js athar/dashboard.css athar/logo.png]
        end
      end

      app.middleware.insert_after Rack::Runtime, Athar::Middleware::AssetServer, root
    end
  end

  class MetadataStackMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      @app.call(env)
    ensure
      MetadataStack.clear!
    end
  end
end
