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

      test "rows with identical occurred_at are returned in numeric id DESC order" do
        # Triggers set both deleted_at and created_at to statement_timestamp(),
        # so any bulk delete in a single statement produces audit rows with
        # identical timestamps. The id column is the only meaningful tiebreaker
        # — and on bigint hosts that means numeric DESC, not lexicographic
        # (`'9' > '10'` lexicographically would interleave incorrectly).
        reset_audit_tables!
        now = Time.utc(2026, 5, 6, 14, 22, 0)

        rows = (1..15).map do |i|
          { record_type: "User", record_id: 1000 + i, actor_type: nil, actor_id: nil,
            schema_name: "public", table_name: "users",
            deleted_at: now, created_at: now,
            record_data: {}, metadata: {} }
        end
        Athar::Deletion.insert_all!(rows)

        ids_in_db = Athar::Deletion.order(id: :desc).pluck(:id)
        feed_ids = FeedQuery.new(filters: filters, now: now, per_page: 50).call.map { |r| r[:id] }

        assert_equal (1..15).to_a.reverse, ids_in_db, "sanity: ids should be 1..15"
        assert_equal ids_in_db, feed_ids,
                     "FeedQuery must order by numeric id DESC and return native types; " \
                     "lexicographic text sort would yield [9, 8, 7, ..., 1, 15, 14, ..., 10]"
      end

      test "kind=delete unions cleanly when audit tables use uuid primary keys" do
        with_uuid_audit_tables do
          deletion_id = SecureRandom.uuid
          truncate_id = SecureRandom.uuid
          now = Time.utc(2026, 5, 6, 14, 22, 0)

          Athar::Deletion.insert_all!(
            [
              { id: deletion_id, record_type: "User", record_id: SecureRandom.uuid,
                actor_type: "User", actor_id: SecureRandom.uuid,
                schema_name: "public", table_name: "users",
                deleted_at: now, created_at: now,
                record_data: {}, metadata: {} }
            ]
          )

          Athar::TableEvent.insert_all!(
            [
              { id: truncate_id, event_type: "truncate",
                schema_name: "public", table_name: "sessions",
                actor_type: nil, actor_id: nil,
                occurred_at: now - 1.hour, created_at: now - 1.hour,
                metadata: {} }
            ]
          )

          delete_only = FeedQuery.new(filters: filters(kind: "delete"), now: now).call
          truncate_only = FeedQuery.new(filters: filters(kind: "truncate"), now: now).call
          all_rows = FeedQuery.new(filters: filters, now: now).call
          delete_total = FeedQuery.new(filters: filters(kind: "delete"), now: now).total
          all_total = FeedQuery.new(filters: filters, now: now).total

          assert_equal 1, delete_only.length
          assert_equal deletion_id, delete_only.first[:id]
          assert_equal "deletion", delete_only.first[:kind]

          assert_equal 1, truncate_only.length
          assert_equal truncate_id, truncate_only.first[:id]

          assert_equal 2, all_rows.length
          assert_equal [deletion_id, truncate_id].sort, all_rows.map { |r| r[:id] }.sort

          assert_equal 1, delete_total
          assert_equal 2, all_total
        end
      end

      test "raises a clear error when audit tables have mismatched id sql_types" do
        # Defensive guard against hand-edited or partially-migrated installs
        # where athar_deletions and athar_table_events drifted apart.
        connection = ActiveRecord::Base.connection
        connection.transaction(requires_new: true) do
          connection.execute("DROP TABLE athar_table_events CASCADE")
          connection.execute(<<~SQL)
            CREATE TABLE athar_table_events (
              id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
              event_type varchar NOT NULL,
              schema_name varchar,
              table_name varchar NOT NULL,
              actor_type varchar,
              actor_id uuid,
              metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
              occurred_at timestamp NOT NULL,
              created_at timestamp NOT NULL
            )
          SQL
          Athar::TableEvent.reset_column_information

          # The divergence check fires up-front in #call/#total, so even the
          # default kind=all (no empty leg) gets a clear ArgumentError instead
          # of a cryptic Postgres UNION error.
          err = assert_raises(ArgumentError) { FeedQuery.new(filters: filters).call }
          assert_match(/mismatched id sql_types/, err.message)
          assert_match(/athar_deletions\.id=bigint/, err.message)
          assert_match(/athar_table_events\.id=uuid/, err.message)

          assert_raises(ArgumentError) { FeedQuery.new(filters: filters).total }
          assert_raises(ArgumentError) { FeedQuery.new(filters: filters(kind: "delete")).call }
          assert_raises(ArgumentError) { FeedQuery.new(filters: filters(kind: "delete")).total }
          assert_raises(ArgumentError) { FeedQuery.new(filters: filters(kind: "truncate")).call }
          assert_raises(ArgumentError) { FeedQuery.new(filters: filters(kind: "truncate")).total }

          raise ActiveRecord::Rollback
        end
      ensure
        Athar::TableEvent.reset_column_information
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
