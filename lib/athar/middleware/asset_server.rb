# frozen_string_literal: true

module Athar
  module Middleware
    # Serves Athar's dashboard assets (`dashboard.js`, `dashboard.css`) directly
    # to hosts that don't have an asset pipeline configured. Rails apps with
    # Sprockets or Propshaft never reach this middleware — the layout helper
    # resolves to a digested asset path served by the asset pipeline.
    #
    # The URL embeds Athar::VERSION as a cache-busting prefix
    # (`/athar-assets/<version>/dashboard.js`); the version segment is stripped
    # before resolving to disk so a single canonical file lives in
    # `app/assets/`. New gem version → new URL → fresh cache.
    class AssetServer
      PREFIX_PATTERN = %r{\A/athar-assets/[^/]+/(.+)\z}

      MIME_TYPES = {
        ".js" => "application/javascript",
        ".css" => "text/css",
        ".png" => "image/png",
        ".svg" => "image/svg+xml"
      }.freeze

      # Where each file extension lives, relative to the engine root.
      EXTENSION_DIRS = {
        ".js" => "app/assets/javascripts/athar",
        ".css" => "app/assets/stylesheets/athar",
        ".png" => "app/assets/images/athar",
        ".svg" => "app/assets/images/athar"
      }.freeze

      def initialize(app, engine_root)
        @app  = app
        @root = File.expand_path(engine_root.to_s)
      end

      def call(env)
        path = env["PATH_INFO"].to_s
        match = PREFIX_PATTERN.match(path)
        return @app.call(env) unless match

        file = resolve(match[1])
        return not_found unless file

        [200, response_headers(file), [File.binread(file)]]
      end

      private

      def resolve(filename)
        ext = File.extname(filename)
        dir = EXTENSION_DIRS[ext]
        return nil unless dir

        source_dir = File.expand_path(dir, @root)
        file = File.expand_path(filename, source_dir)

        return nil unless file.start_with?(source_dir) && File.file?(file)

        file
      end

      def response_headers(file)
        cache = if defined?(::Rails) && ::Rails.env.development?
                  "no-cache, no-store, must-revalidate"
                else
                  "public, max-age=31536000, immutable"
                end

        {
          "Content-Type" => MIME_TYPES[File.extname(file)] || "application/octet-stream",
          "Cache-Control" => cache,
          "Vary" => "Accept-Encoding"
        }
      end

      def not_found
        [404, { "Content-Type" => "text/plain" }, ["Not found"]]
      end
    end
  end
end
