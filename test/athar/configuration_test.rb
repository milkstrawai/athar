# frozen_string_literal: true

require "test_helper"

module Athar
  class ConfigurationTest < ActiveSupport::TestCase
    test "default values" do
      config = Configuration.new

      assert_nil config.logger
      assert_nil config.retention.max_age
      assert_nil config.retention.max_count
      assert_equal 1_000, config.retention.batch_size
      assert_equal 100, config.retention.max_batches_per_run
      assert_equal :athar, config.retention.queue_name
      assert config.retention.prune_table_events
    end

    test "audit table names are fixed v1 constants" do
      assert_equal "athar_deletions", Athar::DELETIONS_TABLE_NAME
      assert_equal "athar_table_events", Athar::TABLE_EVENTS_TABLE_NAME
      assert_equal "athar_deletions", Athar::Deletion.table_name
      assert_equal "athar_table_events", Athar::TableEvent.table_name
    end

    test "configure mutates configuration" do
      Athar.configure do |config|
        config.retention.max_age = 7.days
        config.retention.max_count = 100
        config.retention.batch_size = 50
        config.retention.queue_name = :maintenance
        config.retention.prune_table_events = false
      end

      assert_equal 7.days, Athar.configuration.retention.max_age
      assert_equal 100, Athar.configuration.retention.max_count
      assert_equal 50, Athar.configuration.retention.batch_size
      assert_equal :maintenance, Athar.configuration.retention.queue_name
      refute Athar.configuration.retention.prune_table_events
    end

    test "reset_configuration! returns defaults" do
      Athar.configure { |c| c.retention.max_count = 1 }
      Athar.reset_configuration!

      assert_nil Athar.configuration.retention.max_count
    end

    test "logger falls back to Rails logger when present" do
      assert Athar.logger
    end
  end
end
