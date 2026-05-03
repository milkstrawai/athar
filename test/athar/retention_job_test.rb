# frozen_string_literal: true

require "test_helper"
require "active_job/test_helper"

module Athar
  class RetentionJobTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    test "delegates to Retention.prune!" do
      Retention.expects(:prune!).with(
        max_age: 5.days,
        max_count: 100,
        batch_size: 25,
        max_batches: 3
      ).returns(Retention::Result.new(deleted_by_age: 0, deleted_by_count: 0, table_events_deleted: 0, batches: 0))

      RetentionJob.perform_now(max_age: 5.days, max_count: 100, batch_size: 25, max_batches: 3)
    end

    test "uses configured queue" do
      Athar.configure { |c| c.retention.queue_name = :maintenance }

      assert_equal "maintenance", RetentionJob.new.queue_name
    end

    test "uses athar queue by default" do
      assert_equal "athar", RetentionJob.new.queue_name
    end

    test "perform_later enqueues on the configured queue" do
      Athar.configure { |c| c.retention.queue_name = :maintenance }

      assert_enqueued_with(job: RetentionJob, queue: "maintenance") do
        RetentionJob.perform_later
      end
    end
  end
end
