# frozen_string_literal: true

module Athar
  module Retention
    Result = Struct.new(:deleted_by_age, :deleted_by_count, :table_events_deleted, :batches, keyword_init: true) do
      def total_deleted
        deleted_by_age + deleted_by_count + table_events_deleted
      end
    end

    class << self
      def prune!(max_age: nil, max_count: nil, batch_size: nil, max_batches: nil, prune_table_events: nil) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength,Metrics/PerceivedComplexity
        config = Athar.configuration.retention
        max_age ||= config.max_age
        max_count ||= config.max_count
        batch_size ||= config.batch_size
        max_batches ||= config.max_batches_per_run
        prune_table_events = config.prune_table_events if prune_table_events.nil?

        result = Result.new(deleted_by_age: 0, deleted_by_count: 0, table_events_deleted: 0, batches: 0)

        if max_age
          cutoff = Time.current - max_age
          result.deleted_by_age, age_batches = prune_by_age(
            :athar_deletions,
            "deleted_at",
            cutoff,
            batch_size,
            max_batches
          )
          result.batches += age_batches

          if prune_table_events
            result.table_events_deleted, table_event_batches = prune_by_age(
              :athar_table_events,
              "occurred_at",
              cutoff,
              batch_size,
              [max_batches - result.batches, 0].max
            )
            result.batches += table_event_batches
          end
        end

        if max_count && result.batches < max_batches
          result.deleted_by_count, count_batches = prune_by_count(
            :athar_deletions,
            max_count,
            batch_size,
            max_batches - result.batches
          )
          result.batches += count_batches
        end

        result
      end

      private

      def prune_by_age(table, time_column, cutoff, batch_size, max_batches) # rubocop:disable Metrics/MethodLength
        return [0, 0] if max_batches <= 0

        connection = Athar.audit_connection
        total = 0
        batches = 0
        loop do
          break if batches >= max_batches

          deleted = connection.delete(
            <<~SQL
              DELETE FROM #{table}
              WHERE id IN (
                SELECT id FROM #{table}
                WHERE #{time_column} < #{connection.quote(cutoff)}
                ORDER BY #{time_column} ASC
                LIMIT #{batch_size.to_i}
              )
            SQL
          )
          batches += 1
          total += deleted
          break if deleted < batch_size.to_i
        end

        [total, batches]
      end

      def prune_by_count(table, max_count, batch_size, max_batches) # rubocop:disable Metrics/MethodLength
        return [0, 0] if max_batches <= 0

        connection = Athar.audit_connection
        boundary = connection.select_one(
          <<~SQL
            SELECT deleted_at, id
            FROM #{table}
            ORDER BY deleted_at DESC, id DESC
            OFFSET #{max_count.to_i}
            LIMIT 1
          SQL
        )
        return [0, 0] unless boundary

        boundary_deleted_at = connection.quote(boundary.fetch("deleted_at"))
        boundary_id = connection.quote(boundary.fetch("id"))

        total = 0
        batches = 0
        loop do
          break if batches >= max_batches

          deleted = connection.delete(
            <<~SQL
              DELETE FROM #{table}
              WHERE id IN (
                SELECT id FROM #{table}
                WHERE (deleted_at, id) <= (#{boundary_deleted_at}, #{boundary_id})
                ORDER BY deleted_at ASC, id ASC
                LIMIT #{batch_size.to_i}
              )
            SQL
          )
          batches += 1
          total += deleted
          break if deleted < batch_size.to_i
        end

        [total, batches]
      end
    end
  end
end
