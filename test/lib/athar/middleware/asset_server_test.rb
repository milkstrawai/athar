# frozen_string_literal: true

require "test_helper"
require "athar/middleware/asset_server"

module Athar
  module Middleware
    class AssetServerTest < ActiveSupport::TestCase
      ROOT = Athar::Engine.root.to_s
      INNER_APP = ->(_env) { [200, { "Content-Type" => "text/plain" }, ["pass-through"]] }

      def serve(path)
        env = Rack::MockRequest.env_for(path)
        AssetServer.new(INNER_APP, ROOT).call(env)
      end

      test "serves dashboard.js under /athar-assets/<version>/" do
        status, headers, body = serve("/athar-assets/#{Athar::VERSION}/dashboard.js")

        assert_equal 200, status
        assert_equal "application/javascript", headers["Content-Type"]
        assert_match(/Athar dashboard JS/, body.first)
      end

      test "serves dashboard.css with text/css content type" do
        status, headers, = serve("/athar-assets/#{Athar::VERSION}/dashboard.css")

        assert_equal 200, status
        assert_equal "text/css", headers["Content-Type"]
      end

      test "production cache-control is immutable + 1y" do
        Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("production"))

        _, headers, = serve("/athar-assets/#{Athar::VERSION}/dashboard.js")

        assert_match(/immutable/, headers["Cache-Control"])
        assert_match(/max-age=31536000/, headers["Cache-Control"])
      end

      test "passes through non-asset requests to the inner app" do
        status, _, body = serve("/something/else")

        assert_equal 200, status
        assert_equal ["pass-through"], body
      end

      test "404s for missing asset under the prefix" do
        status, = serve("/athar-assets/#{Athar::VERSION}/missing.js")

        assert_equal 404, status
      end

      test "404s for unsupported file extensions" do
        status, = serve("/athar-assets/#{Athar::VERSION}/dashboard.html")

        assert_equal 404, status
      end

      test "ignores the version segment when resolving on disk" do
        status, _, body = serve("/athar-assets/0.0.0-fake/dashboard.js")

        assert_equal 200, status
        assert_match(/Athar dashboard JS/, body.first)
      end

      test "rejects path traversal attempts" do
        status, = serve("/athar-assets/#{Athar::VERSION}/../../Gemfile")

        assert_equal 404, status
      end
    end
  end
end
