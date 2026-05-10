# frozen_string_literal: true

module Athar
  module Dashboard
    class Sparkline
      DAYS = 14

      def initialize(model:, now: Time.current)
        @model = model
        @now = now
      end

      def buckets # rubocop:disable Metrics/AbcSize
        rows = connection.select_all(<<~SQL).to_a
          SELECT date_trunc('day', deleted_at) AS day, COUNT(*) AS n
          FROM #{Athar::DELETIONS_TABLE_NAME}
          WHERE deleted_at > #{quote(@now - DAYS.days)} #{model_scope}
          GROUP BY day ORDER BY day
        SQL

        by_day = rows.to_h do |row|
          [row["day"].to_date, row["n"].to_i]
        end

        Array.new(DAYS) do |index|
          day = (@now.to_date - (DAYS - 1 - index))
          by_day.fetch(day, 0)
        end
      end

      private

      def model_scope
        @model ? "AND record_type = #{quote(@model)}" : ""
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
