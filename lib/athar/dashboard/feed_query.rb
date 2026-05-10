# frozen_string_literal: true

module Athar
  module Dashboard
    class FeedQuery # rubocop:disable Metrics/ClassLength
      DELETION_SEARCH_COLUMNS = %w[
        record_type record_id::text schema_name table_name
        actor_type actor_id::text record_data::text metadata::text
      ].freeze

      TABLE_EVENT_SEARCH_COLUMNS = %w[
        schema_name table_name actor_type actor_id::text metadata::text
      ].freeze

      def initialize(filters:, per_page: 25, now: Time.current, registry: nil)
        @filters = filters
        @per_page = per_page
        @now = now
        @registry = registry
      end

      def call
        audit_id_type # raise early on type mismatch instead of letting Postgres bubble a cryptic error
        connection.select_all(page_sql, "FeedQuery#call").map { |row| to_row(row) }
      end

      def total
        audit_id_type
        connection.select_value(count_sql, "FeedQuery#total").to_i
      end

      private

      attr_reader :filters, :per_page, :now

      def page_sql
        <<~SQL
          SELECT * FROM (
            #{deletion_select}
            UNION ALL
            #{table_event_select}
          ) feed
          ORDER BY occurred_at DESC, id DESC
          LIMIT #{per_page} OFFSET #{(filters.page - 1) * per_page}
        SQL
      end

      def count_sql
        "SELECT COUNT(*) FROM (#{deletion_select} UNION ALL #{table_event_select}) feed"
      end

      def deletion_select
        return empty_leg_select if filters.kind == "truncate"

        <<~SQL
          SELECT
            'deletion'::text AS kind,
            id,
            record_type,
            record_id::text AS record_id,
            schema_name,
            table_name,
            actor_type,
            actor_id::text AS actor_id,
            deleted_at AS occurred_at,
            record_data,
            metadata
          FROM #{Athar::DELETIONS_TABLE_NAME}
          WHERE #{deletion_where_clause}
        SQL
      end

      def table_event_select
        return empty_leg_select if filters.kind == "delete"

        <<~SQL
          SELECT
            'truncate'::text AS kind,
            id,
            NULL::text AS record_type,
            NULL::text AS record_id,
            schema_name,
            table_name,
            actor_type,
            actor_id::text AS actor_id,
            occurred_at,
            NULL::jsonb AS record_data,
            metadata
          FROM #{Athar::TABLE_EVENTS_TABLE_NAME}
          WHERE event_type = 'truncate' AND #{table_event_where_clause}
        SQL
      end

      def empty_leg_select
        <<~SQL
          SELECT
            NULL::text             AS kind,
            NULL::#{audit_id_type} AS id,
            NULL::text             AS record_type,
            NULL::text             AS record_id,
            NULL::text             AS schema_name,
            NULL::text             AS table_name,
            NULL::text             AS actor_type,
            NULL::text             AS actor_id,
            NULL::timestamptz      AS occurred_at,
            NULL::jsonb            AS record_data,
            NULL::jsonb            AS metadata
          WHERE FALSE
        SQL
      end

      # Native SQL type of the `id` column on both audit tables, used to type
      # the empty UNION leg so it matches the live legs without coercion.
      # The two tables are always created together by the install migration
      # and share the same primary_key_type; we verify that here so a manual
      # divergence raises a clear error rather than a cryptic UNION mismatch.
      def audit_id_type
        @audit_id_type ||= begin
          deletions = connection.columns(Athar::DELETIONS_TABLE_NAME).find { |c| c.name == "id" }.sql_type
          events = connection.columns(Athar::TABLE_EVENTS_TABLE_NAME).find { |c| c.name == "id" }.sql_type

          if deletions != events
            raise ArgumentError,
                  "athar audit tables have mismatched id sql_types: " \
                  "#{Athar::DELETIONS_TABLE_NAME}.id=#{deletions}, " \
                  "#{Athar::TABLE_EVENTS_TABLE_NAME}.id=#{events}"
          end

          deletions
        end
      end

      def deletion_where_clause # rubocop:disable Metrics/AbcSize
        clauses = ["TRUE"]
        clauses << time_clause("deleted_at")
        clauses << "record_type = #{quote(filters.model)}" if filters.model
        # capture_mode is not on the audit row; mode filter operates by table.
        clauses << tables_with_mode_clause(filters.mode) if filters.mode != "all"
        clauses << actor_clause
        clauses << search_clause(DELETION_SEARCH_COLUMNS)
        clauses.compact.join(" AND ")
      end

      def table_event_where_clause # rubocop:disable Metrics/AbcSize
        clauses = ["TRUE"]
        clauses << time_clause("occurred_at")
        clauses << tables_for_model_clause if filters.model
        clauses << tables_with_mode_clause(filters.mode) if filters.mode != "all"
        clauses << actor_clause
        clauses << search_clause(TABLE_EVENT_SEARCH_COLUMNS)
        clauses.compact.join(" AND ")
      end

      def time_clause(column)
        cutoff = filters.time_cutoff(now)
        return nil unless cutoff

        "#{column} >= #{quote(cutoff)}"
      end

      def actor_clause
        actor_filter = filters.actor_filter
        return nil unless actor_filter

        case actor_filter[:kind]
        when :user
          "actor_id::text = #{quote(actor_filter[:id])} AND actor_type = #{quote(actor_filter[:type])}"
        when :sys
          "actor_id IS NULL AND metadata->>'actor' = #{quote(actor_filter[:name])}"
        when :anon
          "actor_id IS NULL AND NOT (metadata ? 'actor')"
        end
      end

      def search_clause(columns)
        query = filters.query.strip
        return nil if query.empty?

        pattern = ActiveRecord::Base.sanitize_sql_like(query)
        like = quote("%#{pattern}%")
        "(#{columns.map { |column| "#{column} ILIKE #{like}" }.join(" OR ")})"
      end

      def tables_for_model_clause
        tables_in_clause(registry.select { |model| model.record_type == filters.model })
      end

      def tables_with_mode_clause(mode)
        tables_in_clause(registry.select { |model| model.capture_mode == mode })
      end

      # Compose `(schema_name, table_name) IN (VALUES …)` from a list of models,
      # or "FALSE" when there are no matching tables — a bare IN over an empty
      # VALUES list is invalid Postgres, so the clause itself collapses.
      def tables_in_clause(models)
        return "FALSE" if models.empty?

        tuples = models.map { |model| "(#{quote(model.schema)}, #{quote(model.table)})" }.join(",")
        "(schema_name, table_name) IN (VALUES #{tuples})"
      end

      def registry
        @registry ||= ModelRegistry.discover
      end

      def quote(value)
        connection.quote(value)
      end

      def connection
        Athar.audit_connection
      end

      def to_row(hash)
        {
          kind: hash["kind"],
          id: hash["id"],
          record_type: hash["record_type"],
          record_id: hash["record_id"],
          schema_name: hash["schema_name"],
          table_name: hash["table_name"],
          actor_type: hash["actor_type"],
          actor_id: hash["actor_id"],
          occurred_at: parse_time(hash["occurred_at"]),
          record_data: parse_jsonb(hash["record_data"]),
          metadata: parse_jsonb(hash["metadata"])
        }
      end

      def parse_time(value)
        return value if value.is_a?(Time)
        return nil if value.nil?

        Time.zone.parse(value.to_s)
      end

      def parse_jsonb(value)
        return value if value.is_a?(Hash) || value.is_a?(Array)
        return nil if value.nil?
        return value unless value.is_a?(String)

        JSON.parse(value)
      rescue JSON::ParserError
        value
      end
    end
  end
end
