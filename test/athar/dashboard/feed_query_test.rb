# frozen_string_literal: true

require "test_helper"

module Athar
  module Dashboard
    class FeedQueryTest < ActiveSupport::TestCase
      setup do
        @now = seed_audit_log!
      end

      test "default scope returns rows ordered by occurred_at desc" do
        rows = FeedQuery.new(filters: filters).call

        assert_predicate rows.length, :positive?
        rows.each_cons(2) { |a, b| assert_operator a[:occurred_at], :>=, b[:occurred_at] }
      end

      test "kind=delete filters out truncate rows" do
        rows = FeedQuery.new(filters: filters(kind: "delete")).call

        assert(rows.all? { |r| r[:kind] == "deletion" })
      end

      test "kind=truncate filters out deletion rows" do
        rows = FeedQuery.new(filters: filters(kind: "truncate")).call

        assert(rows.all? { |r| r[:kind] == "truncate" })
      end

      test "model filter scopes deletion leg by record_type" do
        rows = FeedQuery.new(filters: filters(model: "User")).call.select { |r| r[:kind] == "deletion" }

        assert(rows.all? { |r| r[:record_type] == "User" })
      end

      test "search matches metadata text" do
        rows = FeedQuery.new(filters: filters(q: "req_a")).call

        assert(rows.any? { |r| r[:metadata].to_s.include?("req_a") })
      end

      test "pagination yields stable ordering across pages" do
        all_rows = FeedQuery.new(filters: filters(page: 1), per_page: 5).call
        page2 = FeedQuery.new(filters: filters(page: 2), per_page: 5).call

        refute_equal(all_rows.map { |r| r[:id] }, page2.map { |r| r[:id] })
      end

      test "actor_type collision: same id under different types does not bleed across" do
        Athar::Deletion.delete_all
        Athar::TableEvent.delete_all

        now = Time.utc(2026, 5, 6, 14, 22, 0)
        Athar::Deletion.insert_all!(
          [
            { record_type: "User", record_id: 900, actor_type: "User", actor_id: 5,
              schema_name: "public", table_name: "users",
              deleted_at: now - 1.minute, created_at: now - 1.minute,
              record_data: {}, metadata: {} },
            { record_type: "Admin", record_id: 901, actor_type: "Admin", actor_id: 5,
              schema_name: "public", table_name: "users",
              deleted_at: now - 2.minutes, created_at: now - 2.minutes,
              record_data: {}, metadata: {} }
          ]
        )

        user_rows  = FeedQuery.new(filters: filters(actor: "user:User:5"),  now: now, per_page: 25).call
        admin_rows = FeedQuery.new(filters: filters(actor: "user:Admin:5"), now: now, per_page: 25).call

        assert_equal 1, user_rows.length, "user filter must return exactly the User#5 row"
        assert_equal "User", user_rows.first[:actor_type]

        assert_equal 1, admin_rows.length, "admin filter must return exactly the Admin#5 row"
        assert_equal "Admin", admin_rows.first[:actor_type]
      end

      private

      def filters(**overrides)
        FilterSet.from_params(ActionController::Parameters.new(overrides).permit!)
      end
    end
  end
end
