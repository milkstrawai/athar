# frozen_string_literal: true

require "English"
require "test_helper"
require "active_record/schema_dumper"

module Athar
  class SchemaDumpTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    test "Fx schema.rb round-trip preserves Athar functions and triggers" do
      skip "this test only runs in Fx mode" if ENV["ATHAR_NO_FX"] == "1"

      dumped = dump_schema

      assert_match(/create_function :athar_capture_delete/, dumped)
      assert_match(/create_function :athar_filter_keys/, dumped)
      assert_match(/create_trigger :athar_on_users/, dumped)

      load_schema_into_fresh_database!(dumped)

      assert function_exists?("athar_capture_delete")
      assert function_exists?("athar_filter_keys")
      assert trigger_exists?("users", "athar_on_users")
    end

    test "structure.sql round-trip preserves functions and triggers" do
      skip "this test only runs in --no-fx mode" if ENV["ATHAR_NO_FX"] != "1"

      dumped = dump_structure_sql

      assert_match(/CREATE FUNCTION public\.athar_capture_delete/, dumped)
      assert_match(/CREATE TRIGGER athar_on_users/, dumped)

      load_structure_sql_into_fresh_database!(dumped)

      assert function_exists?("athar_capture_delete")
      assert trigger_exists?("users", "athar_on_users")
    end

    private

    def dump_schema
      io = StringIO.new
      ActiveRecord::Base.connection_pool.with_connection do |_conn|
        ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, io)
      end
      io.string
    end

    def dump_structure_sql
      env = { "PGPASSWORD" => ENV.fetch("ATHAR_DB_PASSWORD", "athar") }
      cmd = [
        "pg_dump",
        "-h", ENV.fetch("ATHAR_DB_HOST", "localhost"),
        "-p", ENV.fetch("ATHAR_DB_PORT", "5434"),
        "-U", ENV.fetch("ATHAR_DB_USER", "athar"),
        "-s", "--no-owner", "--no-privileges",
        ENV.fetch("ATHAR_DB_NAME", "athar_no_fx_test")
      ]
      IO.popen(env, cmd, &:read)
    end

    def load_schema_into_fresh_database!(schema_text)
      conn = ActiveRecord::Base.connection
      conn.execute("DROP SCHEMA IF EXISTS reporting CASCADE")
      conn.execute("DROP TYPE IF EXISTS user_mood CASCADE")
      conn.execute("DROP SCHEMA IF EXISTS public CASCADE")
      conn.execute("CREATE SCHEMA public")
      conn.schema_cache.clear!

      schema_module = Module.new
      schema_module.module_eval(schema_text, "schema.rb")
    ensure
      Athar::TestSupport::DatabaseHelpers.setup!
    end

    def load_structure_sql_into_fresh_database!(structure) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
      conn = ActiveRecord::Base.connection
      conn.execute("DROP SCHEMA IF EXISTS reporting CASCADE")
      conn.execute("DROP TYPE IF EXISTS user_mood CASCADE")
      conn.execute("DROP SCHEMA IF EXISTS public CASCADE")
      conn.execute("CREATE SCHEMA public")
      conn.schema_cache.clear!
      conn.disconnect!

      # Strip newer-version SET statements that aren't supported by older PG servers.
      sanitized = structure.each_line.grep_v(/^\s*SET\s+(transaction_timeout|client_min_messages)/i).join

      Tempfile.create(["athar_structure", ".sql"]) do |file|
        file.write(sanitized)
        file.flush

        env = {
          "PGPASSWORD" => ENV.fetch("ATHAR_DB_PASSWORD", "athar")
        }
        cmd = [
          "psql",
          "-h", ENV.fetch("ATHAR_DB_HOST", "localhost"),
          "-p", ENV.fetch("ATHAR_DB_PORT", "5434"),
          "-U", ENV.fetch("ATHAR_DB_USER", "athar"),
          "-d", ENV.fetch("ATHAR_DB_NAME", "athar_no_fx_test"),
          "-q", "-v", "ON_ERROR_STOP=1",
          "-f", file.path
        ]
        output = IO.popen(env, cmd, err: %i[child out], &:read)
        raise "psql failed to load structure.sql:\n#{output}" unless $CHILD_STATUS.success?
      end

      ActiveRecord::Base.establish_connection
    ensure
      Athar::TestSupport::DatabaseHelpers.setup!
    end
  end
end
