# frozen_string_literal: true

module Athar
  class Engine < ::Rails::Engine
    isolate_namespace Athar

    initializer "athar.set_logger" do
      Athar.configuration.logger ||= Rails.logger
    end
  end
end
