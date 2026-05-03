# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"
require "athar/sql"
require_relative "../fx_helper"

module Athar
  module Generators
    class InstallGenerator < ::Rails::Generators::Base
      include ::Rails::Generators::Migration
      include FxHelper

      source_root File.expand_path("templates", __dir__)

      class_option :update,
                   type: :boolean,
                   default: false,
                   desc: "Generate a function-only migration that updates Athar SQL functions."

      def validate_options!
        ensure_raw_sql_supported! unless fx?
      end

      def write_function_files
        return unless fx?

        FileUtils.mkdir_p(functions_destination)
        function_definitions.each do |function_definition|
          path = File.join(functions_destination, "#{function_definition[:versioned_basename]}.sql")
          next if File.exist?(path) && File.read(path) == function_definition[:body]

          File.write(path, function_definition[:body])
        end
      end

      def generate_migration
        template = fx? ? "install_migration_fx.rb.erb" : "install_migration.rb.erb"
        migration_template template, "db/migrate/#{migration_filename}.rb"
      end

      no_tasks do # rubocop:disable Metrics/BlockLength
        def migration_filename
          if options[:update]
            version = function_definitions.map { |definition| definition[:version] }.max
            "athar_update_functions_v#{version.to_s.rjust(2, "0")}"
          else
            "athar_install"
          end
        end

        def function_definitions # rubocop:disable Metrics/MethodLength
          @function_definitions ||= Athar::SQL::INSTALLED_FUNCTIONS.map do |name|
            previous_version = previous_version_for(name)
            new_body = Athar::SQL.read_function(name, foreign_key_type:)

            version = if previous_version
                        previous_body = read_existing_function(name, previous_version)
                        previous_body == new_body ? previous_version : previous_version + 1
                      else
                        1
                      end

            {
              name:,
              version:,
              previous_version:,
              versioned_basename: "#{name}_v#{version.to_s.rjust(2, "0")}",
              body: new_body,
              signature: Athar::SQL.function_signature(name)
            }
          end
        end

        def previous_version_for(name)
          return nil unless File.directory?(functions_destination)

          Dir.entries(functions_destination)
             .filter_map { |path| path[/\A#{Regexp.escape(name)}_v(\d+)\.sql\z/, 1]&.to_i }
             .max
        end

        def functions_destination
          File.expand_path("db/functions", destination_root)
        end

        def read_existing_function(name, version)
          path = File.join(functions_destination, "#{name}_v#{version.to_s.rjust(2, "0")}.sql")
          File.exist?(path) ? File.read(path) : nil
        end

        def function_drops
          Athar::SQL::INSTALLED_FUNCTIONS.map do |name|
            "DROP FUNCTION IF EXISTS #{name}(#{Athar::SQL.function_signature(name)}) CASCADE;"
          end
        end

        def migration_class_name
          migration_filename.camelize
        end

        def foreign_key_type
          athar_foreign_key_type
        end

        def update?
          options[:update]
        end
      end

      def self.next_migration_number(dir)
        ::ActiveRecord::Generators::Base.next_migration_number(dir)
      end
    end
  end
end
