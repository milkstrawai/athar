# frozen_string_literal: true

require "test_helper"
require "rails/generators/test_case"
require "generators/athar/install/install_generator"

module Athar
  class InstallGeneratorTest < ::Rails::Generators::TestCase
    tests Athar::Generators::InstallGenerator
    destination File.expand_path("../tmp/generators/install", __dir__)
    setup :prepare_destination

    test "Fx mode is the default and writes versioned function files" do
      run_generator

      migration = read_migration("athar_install")

      assert_match(/create_function :athar_filter_keys, version: 1/, migration)
      assert_match(/create_function :athar_capture_delete, version: 1/, migration)
      assert_match(/create_function :athar_capture_truncate, version: 1/, migration)
      assert_match "create_table :athar_deletions", migration
      assert_match "create_table :athar_table_events", migration
      assert_match(/\[:deleted_at, :id\]/, migration)
      assert_match(/add_index :athar_table_events, :occurred_at/, migration)
      assert_match(/index_athar_deletions_on_record_lookup/, migration)
      assert_match(/\[:schema_name, :table_name, :record_id\]/, migration)
      refute_match "add_foreign_key", migration

      assert_path_exists File.join(destination_root, "db/functions/athar_filter_keys_v01.sql")
      assert_path_exists File.join(destination_root, "db/functions/athar_capture_delete_v01.sql")
      assert_path_exists File.join(destination_root, "db/functions/athar_capture_truncate_v01.sql")
    end

    test "update mode emits a function-only migration with update_function" do
      run_generator
      run_generator ["--update"]

      content = read_migration("athar_update_functions_v01")

      refute_match "create_table :athar_deletions", content
      assert_match(/already at version 1/, content)
    end

    test "--update emits create_function for new mask built-ins and bumps athar_capture_delete to v2" do
      # Pre-seed db/functions/ to simulate an app upgrading from the previous release:
      #   - athar_filter_keys at v01 (unchanged body → should stay at v01, no emission)
      #   - athar_capture_delete at v01 (old body → body differs → bump to v02)
      #   - the four new mask functions have no files → new → create_function at v01
      functions_dir = File.join(destination_root, "db/functions")
      FileUtils.mkdir_p(functions_dir)

      File.write(File.join(functions_dir, "athar_capture_delete_v01.sql"), legacy_capture_delete_body)

      unchanged_filter_keys_body = Athar::SQL.read_function("athar_filter_keys")
      File.write(File.join(functions_dir, "athar_filter_keys_v01.sql"), unchanged_filter_keys_body)

      run_generator ["--update"]

      migration = read_migration("athar_update_functions_v02")

      # The four new mask built-ins must be created at v01.
      assert_match(/create_function :athar_apply_masks/, migration)
      assert_match(/create_function :athar_mask_email/, migration)
      assert_match(/create_function :athar_mask_partial/, migration)
      assert_match(/create_function :athar_mask_hash/, migration)

      # athar_capture_delete must be bumped from v01 → v02.
      assert_match(/update_function :athar_capture_delete,\s*\n\s*version: 2,\s*\n\s*revert_to_version: 1/, migration)

      # athar_filter_keys is unchanged — no create_function or update_function for it.
      refute_match(/create_function :athar_filter_keys/, migration)
      refute_match(/update_function :athar_filter_keys/, migration)

      # Sanity: must not emit athar_capture_delete version: 3 (it was at v01, not v02).
      refute_match(/update_function :athar_capture_delete,\s*\n\s*version: 3/, migration)

      # Must not include table DDL — this is a functions-only update migration.
      refute_match "create_table :athar_deletions", migration
    end

    test "--no-fx with schema_format = :sql embeds raw SQL in migration" do
      with_schema_format(:sql) do
        run_generator ["--no-fx"]
      end

      migration = read_migration("athar_install")

      assert_match "execute(<<~SQL)", migration
      assert_match "CREATE OR REPLACE FUNCTION athar_capture_delete()", migration
      refute_match "create_function", migration

      refute File.directory?(File.join(destination_root, "db/functions")),
             "Fx-only db/functions should not be created in raw SQL mode"
    end

    test "--no-fx raises clearly when schema_format = :ruby" do
      with_schema_format(:ruby) do
        generator = Athar::Generators::InstallGenerator.new([], fx: false)
        error = assert_raises(::Thor::Error) { generator.send(:validate_options!) }
        assert_match(/schema_format = :sql/, error.message)
      end
    end

    private

    def legacy_capture_delete_body
      <<~SQL
        CREATE OR REPLACE FUNCTION athar_capture_delete()
        RETURNS trigger AS $$
        BEGIN
          RETURN OLD;
        END;
        $$ LANGUAGE plpgsql;
      SQL
    end

    def read_migration(suffix)
      path = Dir["#{destination_root}/db/migrate/*_#{suffix}.rb"].first

      assert path, "expected migration matching #{suffix}"
      File.read(path)
    end

    def with_schema_format(format)
      previous = Rails.application.config.active_record.schema_format
      Rails.application.config.active_record.schema_format = format
      yield
    ensure
      Rails.application.config.active_record.schema_format = previous
    end
  end
end
