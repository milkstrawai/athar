# frozen_string_literal: true

module Athar
  module Dashboard
    # Database name + Postgres major version, rendered in the topbar.
    class ConnectionInfo
      attr_reader :database, :version

      def self.fetch
        version_num = Athar.audit_connection.select_value("SHOW server_version_num").to_i
        new(database: Athar.audit_db_config.database.to_s, version: "pg#{version_num / 10_000}")
      end

      def initialize(database:, version:)
        @database = database
        @version = version

        freeze
      end
    end
  end
end
