# frozen_string_literal: true

require "test_helper"

module Athar
  class TableEventTest < ActiveSupport::TestCase
    test "truncate scope returns truncate events" do
      ActiveRecord::Base.connection.execute("TRUNCATE TABLE sessions")

      assert_equal 1, TableEvent.truncate.count
    end

    test "for_table filters" do
      ActiveRecord::Base.connection.execute("TRUNCATE TABLE sessions")

      assert_equal 1, TableEvent.for_table("sessions").count
      assert_equal 0, TableEvent.for_table("users").count
    end

    test "recent ordering" do
      ActiveRecord::Base.connection.execute("TRUNCATE TABLE sessions")
      ActiveRecord::Base.connection.execute("TRUNCATE TABLE sessions")

      events = TableEvent.recent

      assert_operator events.first.occurred_at, :>=, events.last.occurred_at
    end

    test "actor lookup tolerates missing class" do
      event = TableEvent.create!(
        event_type: "truncate",
        table_name: "sessions",
        actor_type: "Missing",
        actor_id: 99,
        occurred_at: Time.current,
        created_at: Time.current
      )

      assert_nil event.actor
    end

    test "by_actor requires id when class is passed" do
      error = assert_raises(ArgumentError) { TableEvent.by_actor(ApiClient) }

      assert_match(/id is required/, error.message)
    end
  end
end
