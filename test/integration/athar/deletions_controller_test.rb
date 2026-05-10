# frozen_string_literal: true

require "test_helper"

module Athar
  class DeletionsControllerTest < ActionDispatch::IntegrationTest
    setup { seed_audit_log! }

    test "renders show page for an existing deletion" do
      d = Athar::Deletion.first
      get "/athar/deletions/#{d.id}"

      assert_response :success
      assert_includes response.body, d.record_type
    end

    test "404 for unknown id" do
      get "/athar/deletions/0"

      assert_response :not_found
    end
  end
end
