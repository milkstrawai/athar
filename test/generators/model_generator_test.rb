# frozen_string_literal: true

require "test_helper"
require "rails/generators/test_case"
require "generators/athar/model/model_generator"

module Athar
  class ModelGeneratorTest < ::Rails::Generators::TestCase # rubocop:disable Metrics/ClassLength
    tests Athar::Generators::ModelGenerator
    destination File.expand_path("../tmp/generators/model", __dir__)
    setup :prepare_destination

    test "Fx-default identity migration uses create_trigger" do
      run_generator ["User"]
      content = read_migration("athar_install_users_trigger")

      assert_match(/create_trigger :athar_on_users, on: :users, version: 1/, content)
      assert_path_exists File.join(destination_root, "db/triggers/athar_on_users_v01.sql")

      trigger_sql = File.read(File.join(destination_root, "db/triggers/athar_on_users_v01.sql"))

      assert_match(/CREATE TRIGGER "athar_on_users"/, trigger_sql)
      assert_match(/'identity'/, trigger_sql)
    end

    test "--only Fx migration writes only-mode trigger SQL" do
      run_generator ["User", "--only=email,name"]

      trigger_sql = File.read(File.join(destination_root, "db/triggers/athar_on_users_v01.sql"))

      assert_match(/'only'/, trigger_sql)
      assert_match(/\{email,name\}/, trigger_sql)
    end

    test "--snapshot Fx migration writes snapshot trigger SQL" do
      run_generator ["User", "--snapshot"]

      trigger_sql = File.read(File.join(destination_root, "db/triggers/athar_on_users_v01.sql"))

      assert_match(/'snapshot'/, trigger_sql)
    end

    test "--track-truncate adds an Fx truncate trigger" do
      run_generator ["User", "--track-truncate"]
      content = read_migration("athar_install_users_trigger")

      assert_match(/create_trigger :athar_truncate_on_users, on: :users, version: 1/, content)
      assert_path_exists File.join(destination_root, "db/triggers/athar_truncate_on_users_v01.sql")
    end

    test "--update bumps trigger version with update_trigger" do
      run_generator ["User"]
      run_generator ["User", "--update", "--only=email"]

      content = read_migration("athar_update_users_trigger_v02")

      assert_match(/update_trigger :athar_on_users/, content)
      assert_match(/version: 2/, content)
      assert_match(/revert_to_version: 1/, content)
      assert_path_exists File.join(destination_root, "db/triggers/athar_on_users_v02.sql")
    end

    test "consecutive --update runs produce distinct files and class names" do
      run_generator ["User"]
      run_generator ["User", "--update", "--only=email"]
      run_generator ["User", "--update", "--only=email,name"]

      v2 = Dir["#{destination_root}/db/migrate/*_athar_update_users_trigger_v02.rb"].first
      v3 = Dir["#{destination_root}/db/migrate/*_athar_update_users_trigger_v03.rb"].first

      assert v2, "expected v02 update migration"
      assert v3, "expected v03 update migration"

      v2_class = File.read(v2)[/^class (\w+)/, 1]
      v3_class = File.read(v3)[/^class (\w+)/, 1]

      refute_equal v2_class, v3_class
      assert_match(/V02\z/, v2_class)
      assert_match(/V03\z/, v3_class)
    end

    test "--remove emits drop_trigger" do
      run_generator ["User", "--remove"]
      content = read_migration("athar_remove_users_trigger")

      assert_match(/drop_trigger :athar_on_users, on: :users/, content)
      assert_match(/IrreversibleMigration/, content)
    end

    test "--no-fx with schema_format=:sql embeds raw SQL trigger" do
      with_schema_format(:sql) do
        run_generator ["User", "--no-fx", "--only=email,name"]
      end

      content = read_migration("athar_install_users_trigger")

      assert_match(/CREATE TRIGGER "athar_on_users"/, content)
      assert_match(/DROP TRIGGER IF EXISTS "athar_on_users"/, content)
      assert_match(/'only'/, content)
      refute_match(/create_trigger/, content)

      refute File.directory?(File.join(destination_root, "db/triggers")),
             "Fx-only db/triggers should not be created in raw SQL mode"
    end

    test "--no-fx raises when schema_format is not :sql" do
      with_schema_format(:ruby) do
        generator = Athar::Generators::ModelGenerator.new(["User"], fx: false)
        error = assert_raises(::Thor::Error) { generator.send(:validate_options!) }
        assert_match(/schema_format = :sql/, error.message)
      end
    end

    test "rejects unsafe column names" do
      generator = Athar::Generators::ModelGenerator.new(["User"], only: ["bad name"])
      error = assert_raises(::Thor::Error) { generator.send(:validate_options!) }
      assert_match(/unsafe characters/, error.message)
    end

    test "rejects nonexistent columns" do
      generator = Athar::Generators::ModelGenerator.new(["User"], only: ["does_not_exist"])
      error = assert_raises(::Thor::Error) { generator.send(:validate_options!) }
      assert_match(/not found/, error.message)
    end

    test "rejects --only and --snapshot together" do
      generator = Athar::Generators::ModelGenerator.new(["User"], only: ["email"], snapshot: true)
      error = assert_raises(::Thor::Error) { generator.send(:validate_options!) }
      assert_match(/mutually exclusive/, error.message)
    end

    test "rejects unsafe schema identifier" do
      generator = Athar::Generators::ModelGenerator.new(["User"], schema: %(public"; DROP TABLE x; --))
      error = assert_raises(::Thor::Error) { generator.send(:validate_options!) }
      assert_match(/schema .* not a safe SQL identifier/, error.message)
    end

    test "rejects unsafe primary key identifier" do
      generator = Athar::Generators::ModelGenerator.new(["User"], primary_key: "id; DROP TABLE x")
      error = assert_raises(::Thor::Error) { generator.send(:validate_options!) }
      assert_match(/primary_key .* not a safe SQL identifier/, error.message)
    end

    test "rejects unsafe record-type" do
      generator = Athar::Generators::ModelGenerator.new(["User"], record_type: "User'); DROP")
      error = assert_raises(::Thor::Error) { generator.send(:validate_options!) }
      assert_match(/record_type .* not a safe Ruby class name/, error.message)
    end

    test "non-public schema is inferred from schema-qualified model table name" do
      run_generator ["Reporting::Bucket"]
      content = read_migration("athar_install_reporting_buckets_trigger")
      trigger_sql = File.read(File.join(destination_root, "db/triggers/athar_on_reporting_buckets_v01.sql"))

      assert_match(/on: "reporting\.reporting_buckets"/, content)
      refute_match(/on: :reporting_buckets/, content)
      assert_match(/BEFORE DELETE ON "reporting"."reporting_buckets"/, trigger_sql)
      assert_match(/'reporting'/, trigger_sql)
    end

    test "non-public schema --remove uses schema-qualified Fx on:" do
      run_generator ["Reporting::Bucket", "--remove"]
      content = read_migration("athar_remove_reporting_buckets_trigger")

      assert_match(/drop_trigger :athar_on_reporting_buckets, on: "reporting\.reporting_buckets"/, content)
    end

    test "non-public schema --update uses schema-qualified Fx on:" do
      run_generator ["Reporting::Bucket"]
      run_generator ["Reporting::Bucket", "--update", "--snapshot"]
      content = read_migration("athar_update_reporting_buckets_trigger_v02")

      assert_match(/update_trigger :athar_on_reporting_buckets/, content)
      assert_match(/on: "reporting\.reporting_buckets"/, content)
    end

    test "--schema overrides schema inferred from model table name" do
      run_generator ["Reporting::Bucket", "--schema=archive"]
      content = read_migration("athar_install_reporting_buckets_trigger")
      trigger_sql = File.read(File.join(destination_root, "db/triggers/athar_on_reporting_buckets_v01.sql"))

      assert_match(/on: "archive\.reporting_buckets"/, content)
      assert_match(/BEFORE DELETE ON "archive"."reporting_buckets"/, trigger_sql)
    end

    test "rejects unsafe record-type-column" do
      generator = Athar::Generators::ModelGenerator.new(["User"], record_type_column: "type'); --")
      error = assert_raises(::Thor::Error) { generator.send(:validate_options!) }
      assert_match(/record_type_column .* not a safe SQL identifier/, error.message)
    end

    private

    def read_migration(name)
      path = Dir["#{destination_root}/db/migrate/*_#{name}.rb"].first

      assert path, "expected migration matching #{name}"
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
