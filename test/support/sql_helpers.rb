# frozen_string_literal: true

module Athar
  module TestSupport
    module SqlHelpers
      def query_value(sql, *binds)
        execute_sql(sql, *binds).rows.first&.first
      end

      def execute_sql(sql, *binds)
        ActiveRecord::Base.connection.exec_query(sql, "SQL", binds)
      end
    end
  end
end
