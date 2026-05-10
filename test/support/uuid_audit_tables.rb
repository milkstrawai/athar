# frozen_string_literal: true

module Athar
  module TestSupport
    # Reproduces the production schema where the host app sets
    # `Rails.configuration.generators.options[:active_record][:primary_key_type] = :uuid`,
    # so the install migration creates `athar_deletions` / `athar_table_events`
    # with `uuid` ids and `uuid` polymorphic foreign keys.
    #
    # Runs the block inside a savepoint so the schema swap is rolled back
    # automatically; the `ensure` resets AR column caches so they realign with
    # the restored bigint tables before the next test runs.
    module UuidAuditTables
      def with_uuid_audit_tables # rubocop:disable Metrics/MethodLength
        connection = ActiveRecord::Base.connection
        connection.transaction(requires_new: true) do
          recreate_audit_tables_with_uuid_ids!(connection)
          # Required by both the SUT (FeedQuery's `audit_id_type` reads
          # `connection.columns(...)` via the model's schema cache) and by
          # this helper's own callers, who use `Athar::Deletion.insert_all!`
          # / `Athar::TableEvent.insert_all!` to seed uuid rows. Without the
          # reset, both would still see the bigint columns from before the
          # swap.
          Athar::Deletion.reset_column_information
          Athar::TableEvent.reset_column_information

          yield

          raise ActiveRecord::Rollback
        end
      ensure
        Athar::Deletion.reset_column_information
        Athar::TableEvent.reset_column_information
      end

      private

      def recreate_audit_tables_with_uuid_ids!(connection)
        connection.execute("DROP TABLE athar_deletions CASCADE")
        connection.execute(<<~SQL)
          CREATE TABLE athar_deletions (
            id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
            record_type varchar,
            record_id uuid,
            schema_name varchar,
            table_name varchar NOT NULL,
            actor_type varchar,
            actor_id uuid,
            deleted_at timestamp NOT NULL,
            created_at timestamp NOT NULL,
            record_data jsonb NOT NULL DEFAULT '{}'::jsonb,
            metadata jsonb NOT NULL DEFAULT '{}'::jsonb
          )
        SQL

        connection.execute("DROP TABLE athar_table_events CASCADE")
        connection.execute(<<~SQL)
          CREATE TABLE athar_table_events (
            id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
            event_type varchar NOT NULL,
            schema_name varchar,
            table_name varchar NOT NULL,
            actor_type varchar,
            actor_id uuid,
            metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
            occurred_at timestamp NOT NULL,
            created_at timestamp NOT NULL
          )
        SQL
      end
    end
  end
end
