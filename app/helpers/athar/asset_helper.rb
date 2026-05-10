# frozen_string_literal: true

module Athar
  # Resolves the URL for a dashboard asset (`dashboard.js`, `dashboard.css`).
  #
  # When the host has Sprockets or Propshaft loaded, the asset pipeline serves
  # the digested file from `app/assets/{javascripts,stylesheets}/athar/`.
  # Otherwise we fall through to `/athar-assets/<version>/<name>`, which the
  # `Athar::Middleware::AssetServer` middleware serves directly out of the
  # same `app/assets/` source files.
  module AssetHelper
    def athar_asset_path(name)
      if defined?(::Sprockets) || defined?(::Propshaft)
        begin
          return ActionController::Base.helpers.asset_path("athar/#{name}")
        rescue StandardError => e
          Rails.logger&.warn("[Athar] asset_path fallback for #{name}: #{e.message}")
        end
      end

      "/athar-assets/#{Athar::VERSION}/#{name}"
    end

    def athar_csp_nonce
      respond_to?(:content_security_policy_nonce) ? content_security_policy_nonce : nil
    end
  end
end
