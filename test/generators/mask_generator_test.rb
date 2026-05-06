# frozen_string_literal: true

require "test_helper"
require "rails/generators/test_case"
require "generators/athar/mask/mask_generator"

module Athar
  class MaskGeneratorTest < ::Rails::Generators::TestCase # rubocop:disable Metrics/ClassLength
    tests Athar::Generators::MaskGenerator
    destination File.expand_path("../tmp/generators/mask", __dir__)
    setup :prepare_destination

    test "rejects reserved built-in name 'email'" do
      gen = Athar::Generators::MaskGenerator.new(["email"], regex: ".", replacement: "*")
      error = assert_raises(::Thor::Error) { gen.send(:validate_options!) }
      assert_match(/reserved/, error.message)
    end

    test "rejects reserved built-in name 'partial'" do
      gen = Athar::Generators::MaskGenerator.new(["partial"], regex: ".", replacement: "*")
      error = assert_raises(::Thor::Error) { gen.send(:validate_options!) }
      assert_match(/reserved/, error.message)
    end

    test "rejects reserved built-in name 'hash'" do
      gen = Athar::Generators::MaskGenerator.new(["hash"], regex: ".", replacement: "*")
      error = assert_raises(::Thor::Error) { gen.send(:validate_options!) }
      assert_match(/reserved/, error.message)
    end

    test "rejects unsafe identifier names" do
      gen = Athar::Generators::MaskGenerator.new(["bad name"], regex: ".", replacement: "*")
      error = assert_raises(::Thor::Error) { gen.send(:validate_options!) }
      assert_match(/not a safe SQL identifier/, error.message)
    end

    test "rejects names starting with mask_ to avoid double-prefix confusion" do
      gen = Athar::Generators::MaskGenerator.new(["mask_foo"], regex: ".", replacement: "*")
      error = assert_raises(::Thor::Error) { gen.send(:validate_options!) }
      assert_match(/mask_/, error.message)
    end

    test "requires --regex and --replacement when not removing" do
      gen = Athar::Generators::MaskGenerator.new(["my_mask"], {})
      error = assert_raises(::Thor::Error) { gen.send(:validate_options!) }
      assert_match(/--regex and --replacement are required/, error.message)
    end

    test "rejects --update combined with --remove" do
      gen = Athar::Generators::MaskGenerator.new(["my_mask"], update: true, remove: true)
      error = assert_raises(::Thor::Error) { gen.send(:validate_options!) }
      assert_match(/mutually exclusive/, error.message)
    end

    test "install flow writes function file and migration in fx mode" do
      Dir.mktmpdir do |dir|
        generator = Athar::Generators::MaskGenerator.new(
          ["ssn_keep_last4"],
          regex: "^(\\d{3})-(\\d{2})-(\\d{4})$", replacement: "XXX-XX-\\3"
        )
        generator.destination_root = dir
        generator.invoke_all

        function_file = Dir.glob("#{dir}/db/functions/athar_mask_ssn_keep_last4_v01.sql").first

        assert function_file, "function file should be created"
        body = File.read(function_file)

        assert_includes body, "regexp_replace"
        assert_includes body, "athar_mask_ssn_keep_last4"
        assert_includes body, "(\\d{3})-(\\d{2})-(\\d{4})"
        assert_includes body, "XXX-XX-\\3"

        migration_file = Dir.glob("#{dir}/db/migrate/*_athar_install_mask_ssn_keep_last4.rb").first

        assert migration_file
        assert_includes File.read(migration_file), "create_function :athar_mask_ssn_keep_last4"
      end
    end

    test "install flow writes raw-SQL migration in --no-fx mode" do
      with_schema_format(:sql) do
        Dir.mktmpdir do |dir|
          generator = Athar::Generators::MaskGenerator.new(
            ["upcase"],
            regex: ".", replacement: "X", fx: false
          )
          generator.destination_root = dir
          generator.invoke_all

          migration_file = Dir.glob("#{dir}/db/migrate/*_athar_install_mask_upcase.rb").first

          assert migration_file
          body = File.read(migration_file)

          assert_includes body, "CREATE OR REPLACE FUNCTION athar_mask_upcase"
          assert_includes body, "regexp_replace"
        end
      end
    end

    test "update flow bumps function version in fx mode" do
      Dir.mktmpdir do |dir|
        install = Athar::Generators::MaskGenerator.new(
          ["ssn"],
          regex: ".", replacement: "*"
        )
        install.destination_root = dir
        install.invoke_all

        sleep 1

        update = Athar::Generators::MaskGenerator.new(
          ["ssn"],
          update: true, regex: ".", replacement: "X"
        )
        update.destination_root = dir
        update.invoke_all

        # New _v02.sql file is written
        assert_path_exists "#{dir}/db/functions/athar_mask_ssn_v02.sql"
        # Old _v01.sql still exists (Fx convention preserves history)
        assert_path_exists "#{dir}/db/functions/athar_mask_ssn_v01.sql"

        # _v02 file body uses the new replacement
        body_v02 = File.read("#{dir}/db/functions/athar_mask_ssn_v02.sql")

        assert_includes body_v02, "regexp_replace"
        # The new replacement char 'X' appears (and not the old '*'):
        assert_includes body_v02, "'X'"

        migration = Dir.glob("#{dir}/db/migrate/*_athar_update_mask_ssn_v02.rb").first

        assert migration, "update migration should exist"
        body = File.read(migration)

        assert_includes body, "update_function :athar_mask_ssn"
        assert_includes body, "version: 2"
        assert_includes body, "revert_to_version: 1"
      end
    end

    test "update flow writes raw-SQL migration in --no-fx mode" do
      with_schema_format(:sql) do
        Dir.mktmpdir do |dir|
          install = Athar::Generators::MaskGenerator.new(
            ["upcase"],
            regex: ".", replacement: "X", fx: false
          )
          install.destination_root = dir
          install.invoke_all

          sleep 1

          update = Athar::Generators::MaskGenerator.new(
            ["upcase"],
            update: true, regex: ".", replacement: "Y", fx: false
          )
          update.destination_root = dir
          update.invoke_all

          migration = Dir.glob("#{dir}/db/migrate/*_athar_update_mask_upcase_v02.rb").first

          assert migration
          body = File.read(migration)

          assert_includes body, "CREATE OR REPLACE FUNCTION athar_mask_upcase"
          assert_includes body, "regexp_replace"
          # New replacement Y appears:
          assert_includes body, "'Y'"
        end
      end
    end

    test "remove flow generates drop migration in fx mode" do
      Dir.mktmpdir do |dir|
        Athar::Generators::MaskGenerator.new(
          ["ssn"], regex: ".", replacement: "*"
        ).tap { |g| g.destination_root = dir }.invoke_all
        sleep 1

        Athar::Generators::MaskGenerator.new(
          ["ssn"], remove: true
        ).tap { |g| g.destination_root = dir }.invoke_all

        migration = Dir.glob("#{dir}/db/migrate/*_athar_remove_mask_ssn.rb").first

        assert migration, "remove migration should exist"
        assert_includes File.read(migration), "drop_function :athar_mask_ssn"
      end
    end

    test "remove flow refuses if a model trigger references the mask" do
      Dir.mktmpdir do |dir|
        Athar::Generators::MaskGenerator.new(
          ["ssn"], regex: ".", replacement: "*"
        ).tap { |g| g.destination_root = dir }.invoke_all

        # Simulate an existing model trigger that references this mask.
        FileUtils.mkdir_p("#{dir}/db/triggers")
        File.write(
          "#{dir}/db/triggers/athar_on_users_v01.sql",
          <<~SQL
            EXECUTE PROCEDURE athar_capture_delete(
              'User','public','users','id','bigint','null','snapshot','null','{"ssn:ssn"}'
            )
          SQL
        )

        error = assert_raises(::Thor::Error) do # rubocop:disable Minitest/AssertRaisesCompoundBody
          generator = Athar::Generators::MaskGenerator.new(["ssn"], remove: true)
          generator.destination_root = dir
          generator.send(:validate_options!)
        end

        assert_match(/still referenced by/i, error.message)
      end
    end

    private

    def with_schema_format(format)
      previous = Rails.application.config.active_record.schema_format
      Rails.application.config.active_record.schema_format = format
      yield
    ensure
      Rails.application.config.active_record.schema_format = previous
    end
  end
end
