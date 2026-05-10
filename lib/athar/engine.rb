# frozen_string_literal: true

module Athar
  class Engine < ::Rails::Engine
    isolate_namespace Athar

    initializer "athar.set_logger" do
      Athar.configuration.logger ||= Rails.logger
    end

    initializer "athar.middleware" do |app|
      app.middleware.use MetadataStackMiddleware
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
