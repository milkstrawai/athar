# frozen_string_literal: true

require "test_helper"

module Athar
  class ThemesControllerTest < ActionDispatch::IntegrationTest
    test "PATCH /theme sets cookie and returns 204" do
      patch "/athar/theme", params: { theme: "light" }

      assert_response :no_content
      assert_equal "light", cookies["athar_theme"]
    end

    test "ignores unknown theme values" do
      patch "/athar/theme", params: { theme: "neon" }

      assert_response :unprocessable_entity
    end
  end
end
