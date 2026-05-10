# frozen_string_literal: true

require "strscan"

module Athar
  module Dashboard
    module ModelRegistry
      ModelInfo = Data.define(:schema, :table, :record_type, :capture_mode, :columns, :masks, :sti, :truncate, :count)

      DELETE_TRIGGER_SQL = <<~SQL
        SELECT n.nspname AS schema_name, c.relname AS table_name,
               pg_get_triggerdef(t.oid) AS definition
        FROM pg_trigger t
        JOIN pg_proc p ON p.oid = t.tgfoid
        JOIN pg_class c ON c.oid = t.tgrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE p.proname = 'athar_capture_delete' AND NOT t.tgisinternal
      SQL

      TRUNCATE_TRIGGER_SQL = <<~SQL
        SELECT n.nspname AS schema_name, c.relname AS table_name
        FROM pg_trigger t
        JOIN pg_proc p ON p.oid = t.tgfoid
        JOIN pg_class c ON c.oid = t.tgrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE p.proname = 'athar_capture_truncate' AND NOT t.tgisinternal
      SQL

      COUNTS_SQL = <<~SQL.freeze
        SELECT schema_name, table_name, record_type, COUNT(*) AS n
        FROM #{Athar::DELETIONS_TABLE_NAME}
        GROUP BY schema_name, table_name, record_type
      SQL

      ARGS_RE         = /EXECUTE\s+(?:PROCEDURE|FUNCTION)\s+athar_capture_delete\((.*)\)/m
      PG_ARRAY_QUOTED = /"([^"]*)"/
      PG_ARRAY_BARE   = /[^,]+/

      class << self
        def discover # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength,Metrics/PerceivedComplexity
          connection = Athar.audit_connection
          triggers = parse_delete_triggers(connection)
          truncate_keys = truncate_trigger_keys(connection)
          counts = load_counts(connection)

          # One ModelInfo per (schema, table) trigger.
          primary = triggers.map do |trigger|
            key = [trigger[:schema], trigger[:table]]

            ModelInfo.new(
              schema: trigger[:schema],
              table: trigger[:table],
              record_type: trigger[:record_type] || trigger[:table].classify,
              capture_mode: trigger[:capture_mode],
              columns: trigger[:columns],
              masks: trigger[:masks],
              sti: trigger[:sti],
              truncate: truncate_keys.include?(key),
              count: counts.fetch(
                [trigger[:schema], trigger[:table], trigger[:record_type] || trigger[:table].classify],
                0
              )
            )
          end

          # STI children: any (schema, table, record_type) in counts that doesn't
          # match a primary's record_type but whose (schema, table) has STI on.
          children = counts.filter_map do |(schema, table, record_type), n|
            parent = primary.find { |entry| entry.schema == schema && entry.table == table }
            next unless parent&.sti && parent.record_type != record_type

            ModelInfo.new(
              schema:,
              table:,
              record_type:,
              capture_mode: parent.capture_mode,
              columns: parent.columns,
              masks: parent.masks,
              sti: true,
              truncate: parent.truncate,
              count: n
            )
          end

          primary + children
        end

        private

        def parse_delete_triggers(connection) # rubocop:disable Metrics/AbcSize
          connection.select_all(DELETE_TRIGGER_SQL).map do |row|
            arguments_text = row["definition"][ARGS_RE, 1]
            args = TriggerArgsParser.parse(arguments_text)

            {
              schema: row["schema_name"],
              table: row["table_name"],
              record_type: args[0],
              capture_mode: args[6],
              columns: parse_pg_array(args[7]),
              masks: parse_pg_array(args[8]).map { |spec| spec.split(":").first },
              sti: !args[5].nil?
            }
          end
        end

        def truncate_trigger_keys(connection)
          connection.select_all(TRUNCATE_TRIGGER_SQL).each_with_object(Set.new) do |row, set|
            set << [row["schema_name"], row["table_name"]]
          end
        end

        def load_counts(connection)
          connection.select_all(COUNTS_SQL).to_h do |row|
            [[row["schema_name"], row["table_name"], row["record_type"]], row["n"].to_i]
          end
        end

        # PG array text: '{a,b,c}' or '{"a:b","c:d"}'. Each token is either a
        # "..."-quoted string (content captured) or a bare token up to the
        # next comma.
        def parse_pg_array(text)
          return [] if text.nil? || text == "null"

          inner = text.delete_prefix("{").delete_suffix("}")
          return [] if inner.empty?

          scanner = StringScanner.new(inner)
          parts = []

          until scanner.eos?
            parts << (scanner.scan(PG_ARRAY_QUOTED) ? scanner[1] : scanner.scan(PG_ARRAY_BARE))

            scanner.skip(/,/)
          end

          parts.compact
        end
      end
    end
  end
end
