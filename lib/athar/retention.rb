# frozen_string_literal: true

module Athar
  module Retention
    Result = Struct.new(:deleted_by_age, :deleted_by_count, :table_events_deleted, :batches, keyword_init: true) do
      def total_deleted
        deleted_by_age + deleted_by_count + table_events_deleted
      end
    end

    BatchConfig = Struct.new(:batch_size, :max_batches, :time_column, :primary_key, keyword_init: true) do
      def initialize(batch_size: nil, max_batches: nil, time_column: "deleted_at", primary_key: "id")
        super
      end
    end

    class << self
      def prune!(max_age: nil, max_count: nil, batch_size: nil, max_batches: nil, prune_table_events: nil)
        config = resolve_config(max_age, max_count, batch_size, max_batches, prune_table_events)
        result = Result.new(deleted_by_age: 0, deleted_by_count: 0, table_events_deleted: 0, batches: 0)

        merge_age_results!(result, config) if config[:max_age]
        merge_count_results!(result, config) if config[:max_count] && result.batches < config[:max_batches]

        result
      end

      private

      def resolve_config(max_age, max_count, batch_size, max_batches, prune_table_events)
        cfg = Athar.configuration.retention
        {
          max_age: max_age || cfg.max_age,
          max_count: max_count || cfg.max_count,
          batch_size: batch_size || cfg.batch_size,
          max_batches: max_batches || cfg.max_batches_per_run,
          prune_table_events: prune_table_events.nil? ? cfg.prune_table_events : prune_table_events
        }
      end

      def merge_age_results!(result, config)
        age_result = prune_aged_deletions!(
          cutoff: Time.current - config[:max_age],
          batch_size: config[:batch_size],
          max_batches: config[:max_batches],
          prune_table_events: config[:prune_table_events]
        )
        result.deleted_by_age = age_result[:deleted_by_age]
        result.table_events_deleted = age_result[:table_events_deleted]
        result.batches = age_result[:batches]
      end

      def merge_count_results!(result, config)
        deleted_by_count, count_batches = prune_excess_by_count!(
          max_count: config[:max_count],
          batch_size: config[:batch_size],
          remaining_batches: config[:max_batches] - result.batches
        )
        result.deleted_by_count = deleted_by_count
        result.batches += count_batches
      end

      def prune_aged_deletions!(cutoff:, batch_size:, max_batches:, prune_table_events:)
        deleted_by_age, age_batches = prune_by_age(
          :athar_deletions, "deleted_at", cutoff, batch_size, max_batches
        )

        table_events_deleted = 0
        table_event_batches = 0
        if prune_table_events
          remaining = [max_batches - age_batches, 0].max
          table_events_deleted, table_event_batches = prune_by_age(
            :athar_table_events, "occurred_at", cutoff, batch_size, remaining
          )
        end

        {
          deleted_by_age: deleted_by_age,
          table_events_deleted: table_events_deleted,
          batches: age_batches + table_event_batches
        }
      end

      def prune_excess_by_count!(max_count:, batch_size:, remaining_batches:)
        prune_by_count(
          :athar_deletions, max_count,
          BatchConfig.new(batch_size: batch_size, max_batches: remaining_batches)
        )
      end

      def prune_by_age(table, time_column, cutoff, batch_size, max_batches)
        return [0, 0] if max_batches <= 0

        connection = Athar.audit_connection
        sql = age_delete_sql(connection, table, time_column, cutoff, batch_size)
        batch_delete_loop(connection, sql, batch_size, max_batches)
      end

      def age_delete_sql(connection, table, time_column, cutoff, batch_size)
        <<~SQL
          DELETE FROM #{connection.quote_table_name(table)}
          WHERE id IN (
            SELECT id FROM #{connection.quote_table_name(table)}
            WHERE #{connection.quote_column_name(time_column)} < #{connection.quote(cutoff)}
            ORDER BY #{connection.quote_column_name(time_column)} ASC
            LIMIT #{batch_size.to_i}
          )
        SQL
      end

      def prune_by_count(table, max_count, batch_config)
        return [0, 0] if batch_config.max_batches <= 0

        connection = Athar.audit_connection
        boundary = count_boundary(connection, table, max_count, batch_config)
        return [0, 0] unless boundary

        batch_delete_by_count(connection, table, boundary, batch_config)
      end

      def count_boundary(connection, table, max_count, batch_config)
        connection.select_one(
          <<~SQL
            SELECT #{connection.quote_column_name(batch_config.time_column)},
                   #{connection.quote_column_name(batch_config.primary_key)}
            FROM #{connection.quote_table_name(table)}
            ORDER BY #{connection.quote_column_name(batch_config.time_column)} DESC,
                      #{connection.quote_column_name(batch_config.primary_key)} DESC
            OFFSET #{max_count.to_i}
            LIMIT 1
          SQL
        )
      end

      def batch_delete_by_count(connection, table, boundary, batch_config)
        time_column = batch_config.time_column
        primary_key = batch_config.primary_key
        boundary_time = connection.quote(boundary.fetch(time_column))
        boundary_pk = connection.quote(boundary.fetch(primary_key))
        sql = count_delete_sql(connection, table, boundary_time, boundary_pk, batch_config)
        batch_delete_loop(connection, sql, batch_config.batch_size, batch_config.max_batches)
      end

      def count_delete_sql(connection, table, boundary_time, boundary_pk, batch_config)
        time_column = batch_config.time_column
        primary_key = batch_config.primary_key
        <<~SQL
          DELETE FROM #{connection.quote_table_name(table)}
          WHERE #{connection.quote_column_name(primary_key)} IN (
            SELECT #{connection.quote_column_name(primary_key)} FROM #{connection.quote_table_name(table)}
            WHERE (#{connection.quote_column_name(time_column)}, #{connection.quote_column_name(primary_key)}) <= (#{boundary_time}, #{boundary_pk})
            ORDER BY #{connection.quote_column_name(time_column)} ASC, #{connection.quote_column_name(primary_key)} ASC
            LIMIT #{batch_config.batch_size.to_i}
          )
        SQL
      end

      def batch_delete_loop(connection, sql, batch_size, max_batches)
        total = 0
        batches = 0
        loop do
          break if batches >= max_batches

          deleted = connection.delete(sql)
          batches += 1
          total += deleted
          break if deleted < batch_size.to_i
        end

        [total, batches]
      end
    end
  end
end
