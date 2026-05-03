# frozen_string_literal: true

module Athar
  DELETIONS_TABLE_NAME = "athar_deletions"
  TABLE_EVENTS_TABLE_NAME = "athar_table_events"

  class Configuration
    attr_accessor :logger

    attr_reader :retention

    def initialize
      @logger = nil
      @retention = RetentionConfiguration.new
    end

    class RetentionConfiguration
      attr_accessor :max_age,
                    :max_count,
                    :batch_size,
                    :max_batches_per_run,
                    :queue_name,
                    :prune_table_events

      def initialize
        @max_age = nil
        @max_count = nil
        @batch_size = 1_000
        @max_batches_per_run = 100
        @queue_name = :athar
        @prune_table_events = true
      end
    end
  end
end
