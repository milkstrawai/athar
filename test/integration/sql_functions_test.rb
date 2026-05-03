# frozen_string_literal: true

require "test_helper"

module Athar
  class SqlFunctionsTest < ActiveSupport::TestCase
    test "athar_filter_keys keeps listed keys" do
      result = filter_keys('{"id":1,"email":"a@b","token":"sec"}', ["email"])

      assert_equal({ "email" => "a@b" }, result)
    end

    test "athar_filter_keys ignores missing keys" do
      result = filter_keys('{"id":1}', ["nope"])

      assert_equal({}, result)
    end

    test "athar_filter_keys empty include returns empty object" do
      result = filter_keys('{"a":1}', [])

      assert_equal({}, result)
    end

    test "STI record_type captured from row" do
      Admin.create!(email: "admin@example.com").destroy!

      assert_equal "Admin", Deletion.last.record_type
    end

    test "JSONB preserves array, jsonb, and timestamp as string in record_data" do
      user = User.create!(
        email: "j@example.com",
        name: "Jay",
        status: "vip",
        tags: %w[alpha beta],
        preferences: { theme: "dark" }
      )

      user.destroy!

      data = Deletion.last.record_data

      assert_equal %w[alpha beta], data["tags"]
      assert_equal({ "theme" => "dark" }, data["preferences"])
    end

    private

    def filter_keys(data_json, cols)
      pg_cols = "{#{cols.join(",")}}"
      ActiveRecord::Base.connection.select_value(
        ActiveRecord::Base.sanitize_sql_array([
                                                "SELECT athar_filter_keys(?::jsonb, ?::text[])::text",
                                                data_json, pg_cols
                                              ])
      ).then { |s| JSON.parse(s) }
    end
  end
end
