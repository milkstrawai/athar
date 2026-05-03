# frozen_string_literal: true

require "test_helper"

module Athar
  class RetentionTest < ActiveSupport::TestCase
    setup do
      Deletion.delete_all
      TableEvent.delete_all
    end

    test "prunes deletions older than max_age" do
      old = travel_to(2.years.ago) { create_deletion! }
      young = create_deletion!

      Retention.prune!(max_age: 1.year)

      refute Deletion.exists?(old.id)
      assert Deletion.exists?(young.id)
    end

    test "keeps newest max_count rows" do
      6.times { create_deletion! }

      Retention.prune!(max_count: 4)

      assert_equal 4, Deletion.count
    end

    test "keeps exact max_count when deletion timestamps match" do
      travel_to Time.current.change(usec: 0) do
        6.times { create_deletion! }
      end

      Retention.prune!(max_count: 4)

      assert_equal 4, Deletion.count
    end

    test "age pruning runs before count pruning" do
      4.times { travel_to(2.years.ago) { create_deletion! } }
      2.times { create_deletion! }

      Retention.prune!(max_age: 1.year, max_count: 1)

      assert_equal 1, Deletion.count
    end

    test "deletes count-pruned rows across multiple batches" do
      10.times { create_deletion! }

      result = Retention.prune!(max_count: 0, batch_size: 3)

      assert_equal 0, Deletion.count
      assert_equal 4, result.batches
      assert_equal 10, result.deleted_by_count
    end

    test "respects max_batches_per_run" do
      10.times { create_deletion! }

      result = Retention.prune!(max_count: 0, batch_size: 1, max_batches: 3)

      assert_equal 7, Deletion.count
      assert_equal 3, result.batches
    end

    test "prunes table events when enabled" do
      old = travel_to(2.years.ago) { create_event! }
      young = create_event!

      Retention.prune!(max_age: 1.year, prune_table_events: true)

      refute TableEvent.exists?(old.id)
      assert TableEvent.exists?(young.id)
    end

    test "does not prune table events when disabled" do
      old = travel_to(2.years.ago) { create_event! }

      Retention.prune!(max_age: 1.year, prune_table_events: false)

      assert TableEvent.exists?(old.id)
    end

    test "result returns counts" do
      travel_to(2.years.ago) { create_deletion! }
      result = Retention.prune!(max_age: 1.year)

      assert_equal 1, result.deleted_by_age
    end

    test "no-op when neither max_age nor max_count is configured" do
      3.times { create_deletion! }

      result = Retention.prune!

      assert_equal 0, result.total_deleted
      assert_equal 0, result.batches
      assert_equal 3, Deletion.count
    end

    private

    def create_deletion!
      Deletion.create!(
        record_type: "User",
        record_id: rand(1..100_000),
        table_name: "users",
        deleted_at: Time.current,
        created_at: Time.current
      )
    end

    def create_event!
      TableEvent.create!(
        event_type: "truncate",
        table_name: "users",
        occurred_at: Time.current,
        created_at: Time.current
      )
    end
  end
end
