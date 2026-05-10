# frozen_string_literal: true

require "test_helper"

module Athar
  class TableEventsControllerTest < ActionDispatch::IntegrationTest
    setup { seed_audit_log! }

    test "renders show page for an existing table event" do
      e = Athar::TableEvent.first
      get "/athar/table_events/#{e.id}"

      assert_response :success
      assert_includes response.body, e.table_name
    end
  end
end
