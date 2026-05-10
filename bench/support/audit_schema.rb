# frozen_string_literal: true

require_relative "../../lib/athar"

module Bench
  module AuditSchema
    class << self
      def install!(connection, foreign_key_type: "bigint")
        connection.execute(audit_schema_sql(foreign_key_type))

        Athar::SQL.all_functions(foreign_key_type:).each_value do |body|
          connection.execute(body)
        end
      end

      def install_delete_trigger(connection, trigger_name:, table_name:, record_type:, capture_mode:, columns: nil) # rubocop:disable Metrics/ParameterLists
        connection.execute("DROP TRIGGER IF EXISTS #{trigger_name} ON #{table_name}")
        return if capture_mode == :none

        columns_arg = columns ? "'{#{columns.join(",")}}'" : "'__athar_none__'"

        connection.execute(<<~SQL)
          CREATE TRIGGER #{trigger_name}
          BEFORE DELETE ON #{table_name}
          FOR EACH ROW
          WHEN (coalesce(current_setting('athar.disabled', true), '') <> 'on')
          EXECUTE PROCEDURE athar_capture_delete(
            '#{record_type}', 'public', '#{table_name}', 'id', 'bigint', '__athar_none__',
            '#{capture_mode}', #{columns_arg}
          );
        SQL
      end

      private

      def audit_schema_sql(foreign_key_type)
        <<~SQL
          CREATE TABLE athar_deletions (
            id bigserial PRIMARY KEY,
            record_type text NOT NULL,
            record_id #{foreign_key_type} NOT NULL,
            actor_type text,
            actor_id #{foreign_key_type},
            schema_name text,
            table_name text NOT NULL,
            deleted_at timestamp NOT NULL,
            created_at timestamp NOT NULL,
            record_data jsonb DEFAULT '{}'::jsonb NOT NULL,
            metadata jsonb DEFAULT '{}'::jsonb NOT NULL
          );

          CREATE INDEX index_athar_deletions_on_record
            ON athar_deletions (record_type, record_id);
          CREATE INDEX index_athar_deletions_on_actor
            ON athar_deletions (actor_type, actor_id);
          CREATE INDEX index_athar_deletions_on_deleted_at_id
            ON athar_deletions (deleted_at, id);
          CREATE INDEX index_athar_deletions_on_table_deleted_at
            ON athar_deletions (table_name, deleted_at);
          CREATE INDEX index_athar_deletions_on_record_lookup
            ON athar_deletions (schema_name, table_name, record_id);

          CREATE TABLE athar_table_events (
            id bigserial PRIMARY KEY,
            event_type text NOT NULL,
            schema_name text,
            table_name text NOT NULL,
            actor_type text,
            actor_id #{foreign_key_type},
            metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
            occurred_at timestamp NOT NULL,
            created_at timestamp NOT NULL
          );

          CREATE INDEX index_athar_table_events_on_actor
            ON athar_table_events (actor_type, actor_id);
          CREATE INDEX index_athar_table_events_on_type_table_time
            ON athar_table_events (event_type, table_name, occurred_at);
          CREATE INDEX index_athar_table_events_on_occurred_at
            ON athar_table_events (occurred_at);
        SQL
      end
    end
  end
end
