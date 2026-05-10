# frozen_string_literal: true

module Athar
  module Dashboard
    class KpiCalculator
      Result = Data.define(
        :scope_total,
        :last_24h,
        :last_7d,
        :prior_7d,
        :distinct_actors_30d,
        :truncates_30d,
        :sparkline
      )

      def initialize(model:, now: Time.current, registry: nil)
        @model = model
        @now = now
        @registry = registry
      end

      def call(connection: ActiveRecord::Base.connection) # rubocop:disable Metrics/AbcSize
        aggregates = aggregate(connection)
        truncates_30d = truncate_count(connection)

        Result.new(
          # scope_total covers the same universe the feed UNIONs over: row
          # deletions plus all table events for the model's tables (not just
          # the last 30d), so "filtered N of M" never overshoots M.
          scope_total: aggregates["scope_total"].to_i + table_event_total(connection),
          last_24h: aggregates["last_24h"].to_i,
          last_7d: aggregates["last_7d"].to_i,
          prior_7d: aggregates["prior_7d"].to_i,
          distinct_actors_30d: aggregates["distinct_actors_30d"].to_i,
          truncates_30d: truncates_30d,
          sparkline: Sparkline.new(model: @model, now: @now).buckets(connection: connection)
        )
      end

      private

      def aggregate(connection) # rubocop:disable Metrics/AbcSize
        sql = <<~SQL
          SELECT
            COUNT(*) AS scope_total,
            COUNT(*) FILTER (WHERE deleted_at > #{quote(@now - 1.day)}) AS last_24h,
            COUNT(*) FILTER (WHERE deleted_at > #{quote(@now - 7.days)}) AS last_7d,
            COUNT(*) FILTER (WHERE deleted_at > #{quote(@now - 14.days)}
                               AND deleted_at <= #{quote(@now - 7.days)}) AS prior_7d,
            COUNT(DISTINCT (actor_type, actor_id))
              FILTER (WHERE actor_id IS NOT NULL AND deleted_at > #{quote(@now - 30.days)}) AS distinct_actors_30d
          FROM #{Athar::DELETIONS_TABLE_NAME}
          #{model_scope}
        SQL

        connection.select_one(sql)
      end

      def truncate_count(connection)
        sql = <<~SQL
          SELECT COUNT(*) AS n FROM #{Athar::TABLE_EVENTS_TABLE_NAME}
          WHERE event_type = 'truncate' AND occurred_at > #{quote(@now - 30.days)}
          #{table_scope_clause}
        SQL
        connection.select_value(sql).to_i
      end

      def table_event_total(connection)
        sql = <<~SQL
          SELECT COUNT(*) AS n FROM #{Athar::TABLE_EVENTS_TABLE_NAME}
          WHERE TRUE #{table_scope_clause}
        SQL

        connection.select_value(sql).to_i
      end

      def model_scope
        return "" unless @model

        "WHERE record_type = #{quote(@model)}"
      end

      def table_scope_clause
        return "" unless @model

        scoped = registry.select { |model| model.record_type == @model }
        return "AND FALSE" if scoped.empty?

        pairs = scoped.map { |model| "(#{quote(model.schema)}, #{quote(model.table)})" }.join(",")
        "AND (schema_name, table_name) IN (VALUES #{pairs})"
      end

      def registry
        @registry ||= ModelRegistry.discover
      end

      def quote(value)
        ActiveRecord::Base.connection.quote(value)
      end
    end
  end
end
