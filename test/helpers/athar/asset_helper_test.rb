# frozen_string_literal: true

require "test_helper"

module Athar
  class AssetHelperTest < ActionView::TestCase
    include Athar::AssetHelper

    test "falls back to versioned middleware path when no asset pipeline is loaded" do
      hide_const = ->(name) { Object.send(:remove_const, name) if Object.const_defined?(name) }
      sprockets_was = Object.const_defined?(:Sprockets) ? Object.const_get(:Sprockets) : nil
      propshaft_was = Object.const_defined?(:Propshaft) ? Object.const_get(:Propshaft) : nil

      hide_const.call(:Sprockets)
      hide_const.call(:Propshaft)

      assert_equal "/athar-assets/#{Athar::VERSION}/dashboard.js", athar_asset_path("dashboard.js")
    ensure
      Object.const_set(:Sprockets, sprockets_was) if sprockets_was
      Object.const_set(:Propshaft, propshaft_was) if propshaft_was
    end

    test "uses asset pipeline when Sprockets/Propshaft is loaded" do
      skip "asset pipeline not loaded in this dummy" unless defined?(::Sprockets) || defined?(::Propshaft)

      ActionController::Base.helpers.stubs(:asset_path).with("athar/dashboard.js").returns("/assets/athar/dashboard-abc.js")

      assert_equal "/assets/athar/dashboard-abc.js", athar_asset_path("dashboard.js")
    end

    test "athar_csp_nonce returns nil when content_security_policy_nonce is not defined" do
      assert_nil athar_csp_nonce
    end
  end
end
