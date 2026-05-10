# frozen_string_literal: true

module Athar
  module Dashboard
    class ActorOptions
      Result = Data.define(:users, :system, :anonymous_label)
      LIMIT  = 50

      def initialize(cutoff:)
        @cutoff = cutoff
      end

      def call
        Result.new(
          users: load_users,
          system: load_system,
          anonymous_label: "(anonymous)"
        )
      end

      private

      def load_users # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
        rows = connection.select_all(<<~SQL).to_a
          SELECT actor_type, actor_id::text AS actor_id, MAX(deleted_at) AS last_seen
          FROM #{Athar::DELETIONS_TABLE_NAME}
          WHERE actor_id IS NOT NULL AND deleted_at >= #{quote(@cutoff)}
          GROUP BY actor_type, actor_id
          ORDER BY last_seen DESC
          LIMIT #{LIMIT}
        SQL

        rows.group_by { |row| row["actor_type"] }.flat_map do |type, rows_for_type|
          klass = type.safe_constantize

          if klass.respond_to?(:where)
            ids = rows_for_type.map { |row| row["actor_id"] }
            records_by_id = klass.where(klass.primary_key => ids).index_by { |record| record.id.to_s }

            rows_for_type.map do |row|
              record = records_by_id[row["actor_id"]]
              { value: "user:#{row["actor_type"]}:#{row["actor_id"]}",
                label: ActorLabels.humanize(record, type, row["actor_id"]) }
            end
          else
            rows_for_type.map do |row|
              { value: "user:#{row["actor_type"]}:#{row["actor_id"]}", label: "#{type}##{row["actor_id"]}" }
            end
          end
        end
      end

      def load_system
        rows = connection.select_all(<<~SQL).to_a
          SELECT metadata->>'actor' AS name, MAX(deleted_at) AS last_seen
          FROM #{Athar::DELETIONS_TABLE_NAME}
          WHERE actor_id IS NULL AND metadata ? 'actor' AND deleted_at >= #{quote(@cutoff)}
          GROUP BY 1
          ORDER BY last_seen DESC
          LIMIT #{LIMIT}
        SQL

        rows.map { |row| { value: "sys:#{row["name"]}", label: row["name"] } }
      end

      def quote(value)
        connection.quote(value)
      end

      def connection
        Athar.audit_connection
      end
    end
  end
end
