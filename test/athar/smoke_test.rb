# frozen_string_literal: true

require "test_helper"

module Athar
  class SmokeTest < ActiveSupport::TestCase
    test "Athar gem loads" do
      assert defined?(Athar::VERSION)
      assert_kind_of String, Athar::VERSION
    end

    test "schema migrations created audit tables" do
      assert ActiveRecord::Base.connection.table_exists?("athar_deletions")
      assert ActiveRecord::Base.connection.table_exists?("athar_table_events")
    end

    test "trigger function is installed" do
      assert function_exists?("athar_capture_delete")
      assert function_exists?("athar_filter_keys")
      assert function_exists?("athar_capture_truncate")
    end

    test "users trigger is installed" do
      assert trigger_exists?("users", "athar_on_users")
    end

    test "for_record lookup index exists on athar_deletions" do
      indexes = ActiveRecord::Base.connection.indexes("athar_deletions").map(&:name)

      assert_includes indexes, "index_athar_deletions_on_record_lookup"
    end

    test "retention indexes exist" do
      deletion_indexes = ActiveRecord::Base.connection.indexes("athar_deletions").map(&:columns)
      table_event_indexes = ActiveRecord::Base.connection.indexes("athar_table_events").map(&:columns)

      assert_includes deletion_indexes, %w[deleted_at id]
      assert_includes table_event_indexes, %w[occurred_at]
    end
  end
end
