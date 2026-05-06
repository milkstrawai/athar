# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"
require_relative "../fx_helper"

module Athar
  module Generators
    class MaskGenerator < ::Rails::Generators::NamedBase # rubocop:disable Metrics/ClassLength
      include ::Rails::Generators::Migration
      include FxHelper

      RESERVED_MASK_NAMES = %w[email partial hash].freeze
      SAFE_IDENTIFIER_REGEX = /\A[A-Za-z_][A-Za-z0-9_]*\z/

      source_root File.expand_path("templates", __dir__)

      argument :name, type: :string, banner: "MaskName"

      class_option :regex, type: :string,
                           default: nil, desc: "Regex pattern passed to PostgreSQL regexp_replace"
      class_option :replacement, type: :string, default: nil,
                                 desc: "Replacement string (use \\1, \\2, etc. for capture groups)"
      class_option :flags, type: :string, default: "g",
                           desc: "Flags for regexp_replace (default 'g')"
      class_option :update, type: :boolean, default: false,
                            desc: "Generate an update migration that bumps the function version"
      class_option :remove, type: :boolean, default: false,
                            desc: "Generate a removal migration that drops the function"

      def validate_options!
        validate_name!
        validate_action!
        validate_no_active_references! if remove?
        ensure_raw_sql_supported! unless fx?
      end

      def write_function_file
        return unless fx? && !remove?

        FileUtils.mkdir_p(functions_destination)
        version = next_version.to_s.rjust(2, "0")
        path = File.join(functions_destination, "athar_mask_#{name}_v#{version}.sql")
        File.write(path, function_body)
      end

      def generate_migration
        template_name =
          if remove?
            fx? ? "remove_migration_fx.rb.erb" : "remove_migration.rb.erb"
          elsif update?
            fx? ? "update_migration_fx.rb.erb" : "update_migration.rb.erb"
          else
            fx? ? "install_migration_fx.rb.erb" : "install_migration.rb.erb"
          end
        migration_template template_name, "db/migrate/#{migration_filename}.rb"
      end

      no_tasks do # rubocop:disable Metrics/BlockLength
        def update? = options.[](:update)
        def remove? = options.[](:remove)
        def function_name = "athar_mask_#{name}"

        def function_body
          template_path = File.join(__dir__, "functions/athar_mask_regex.sql.erb")
          ERB.new(File.read(template_path), trim_mode: "-").result(binding)
        end

        def migration_filename
          if remove?
            "athar_remove_mask_#{name}"
          elsif update?
            "athar_update_mask_#{name}_v#{next_version.to_s.rjust(2, "0")}"
          else
            "athar_install_mask_#{name}"
          end
        end

        def migration_class_name
          migration_filename.camelize
        end

        def functions_destination
          File.expand_path("db/functions", destination_root)
        end

        def pg_quote(value)
          return "''" if value.nil?

          "'#{value.to_s.gsub("'", "''")}'"
        end

        def next_version
          @next_version ||= previous_version_for_mask + 1
        end

        def previous_version_for_mask # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength,Metrics/PerceivedComplexity
          # In fx mode, determine version from .sql files in db/functions/
          if fx? && File.directory?(functions_destination)
            sql_version = Dir.entries(functions_destination)
                             .filter_map { |f| f[/\Aathar_mask_#{Regexp.escape(name)}_v(\d+)\.sql\z/, 1]&.to_i }
                             .max

            return sql_version if sql_version
          end

          # Fallback: determine version from existing migration filenames.
          # Install migration has no version suffix (counts as v1 when present).
          # Update migrations have _vNN suffix.
          migrations_dir = File.expand_path("db/migrate", destination_root)
          return 0 unless File.directory?(migrations_dir)

          install_exists = Dir.entries(migrations_dir).any? do |f|
            f.match?(/\d+_athar_install_mask_#{Regexp.escape(name)}\.rb\z/)
          end

          update_versions = Dir.entries(migrations_dir).filter_map do |f|
            f[/\d+_athar_update_mask_#{Regexp.escape(name)}_v(\d+)\.rb\z/,
              1]&.to_i
          end

          max_update = update_versions.max

          if max_update
            max_update
          elsif install_exists
            1
          else
            0
          end
        end
      end

      def self.next_migration_number(dir)
        ::ActiveRecord::Generators::Base.next_migration_number(dir)
      end

      private

      def validate_name!
        raise_invalid("name #{name.inspect} is not a safe SQL identifier") unless name.match?(SAFE_IDENTIFIER_REGEX)
        raise_invalid("name #{name.inspect} is reserved (built-in mask)") if RESERVED_MASK_NAMES.include?(name)
        return unless name.start_with?("mask_")

        raise_invalid("name should not start with 'mask_' (the function will already be prefixed athar_mask_)")
      end

      def validate_action!
        raise_invalid("--update and --remove are mutually exclusive") if update? && remove?
        return if remove?
        return if options[:regex] && options[:replacement]

        raise_invalid("--regex and --replacement are required (unless --remove)")
      end

      def validate_no_active_references!
        references = scan_for_mask_references(name)
        return if references.empty?

        raise_invalid(
          "cannot remove athar_mask_#{name}; still referenced by:\n  - " + # rubocop:disable Style/StringConcatenation
          references.join("\n  - ") +
          "\nRegenerate those model triggers without this mask first."
        )
      end

      def scan_for_mask_references(mask_name) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
        results = []

        triggers_dir = File.join(destination_root, "db/triggers")
        if Dir.exist?(triggers_dir)
          Dir.glob(File.join(triggers_dir, "*.sql")).each do |path|
            results << path if File.read(path).include?(":#{mask_name}\"")
          end
        end

        migrate_dir = File.join(destination_root, "db/migrate")
        if Dir.exist?(migrate_dir)
          Dir.glob(File.join(migrate_dir, "*.rb")).each do |path|
            results << path if File.read(path).include?(":#{mask_name}\"")
          end
        end

        results
      end

      def raise_invalid(message)
        raise ::Thor::Error, "Athar mask generator error: #{message}"
      end
    end
  end
end
