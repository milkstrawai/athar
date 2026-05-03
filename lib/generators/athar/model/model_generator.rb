# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"
require "athar/sql"
require_relative "../fx_helper"

module Athar
  module Generators
    class ModelGenerator < ::Rails::Generators::NamedBase # rubocop:disable Metrics/ClassLength
      include ::Rails::Generators::Migration
      include FxHelper

      ALLOWED_ID_TYPES = %w[bigint integer uuid].freeze
      CAPTURE_MODES = %w[identity only snapshot].freeze
      UNSAFE_COLUMN_REGEX = /[\s,{}"\\']/
      # PostgreSQL unquoted identifier surface: starts with letter or _,
      # then letters/digits/underscores. Matches what the generator embeds
      # inside both `"identifier"` and `'string'` SQL contexts.
      SAFE_IDENTIFIER_REGEX = /\A[A-Za-z_][A-Za-z0-9_]*\z/
      # Ruby class names, with optional `::` namespacing.
      SAFE_CLASS_NAME_REGEX = /\A[A-Z][A-Za-z0-9_]*(::[A-Z][A-Za-z0-9_]*)*\z/

      source_root File.expand_path("templates", __dir__)

      argument :name, type: :string, banner: "ModelName"

      class_option :only, type: :array, default: nil, desc: "Capture only the listed columns. Comma-separated."
      class_option :snapshot, type: :boolean, default: false, desc: "Capture all row attributes."
      class_option :primary_key, type: :string, default: nil, desc: "Primary key column."
      class_option :record_type, type: :string, default: nil, desc: "Override the stored record_type."
      class_option :record_type_column, type: :string, default: nil, desc: "STI column. Pass 'false' to disable."
      class_option :schema, type: :string, default: nil, desc: "PostgreSQL schema."
      class_option :track_truncate, type: :boolean, default: false, desc: "Install AFTER TRUNCATE trigger."
      class_option :update, type: :boolean, default: false, desc: "Generate an update migration."
      class_option :remove, type: :boolean, default: false, desc: "Generate a removal migration."

      def validate_options!
        validate_capture_mode!
        validate_identifiers!
        validate_id_type!
        validate_columns!
        ensure_raw_sql_supported! unless fx?
      end

      def write_trigger_files # rubocop:disable Metrics/AbcSize
        return unless fx?
        return if remove?

        FileUtils.mkdir_p(triggers_destination)
        # Reading trigger_descriptors first caches the version computation
        # against the on-disk state *before* we write the new files.
        trigger_descriptors.each do |descriptor|
          path = File.join(
            triggers_destination,
            "#{descriptor[:name]}_v#{descriptor[:version].to_s.rjust(2, "0")}.sql"
          )
          next if File.exist?(path) && File.read(path) == descriptor[:body]

          File.write(path, descriptor[:body])
        end
      end

      def generate_migration
        template = fx? ? "migration_fx.rb.erb" : "migration.rb.erb"
        migration_template template, "db/migrate/#{migration_filename}.rb"
      end

      no_tasks do # rubocop:disable Metrics/BlockLength
        def trigger_descriptors
          @trigger_descriptors ||= begin
            descriptors = []
            unless remove?
              descriptors << build_descriptor(trigger_name, render_trigger("athar_delete"))
              if track_truncate?
                descriptors << build_descriptor(truncate_trigger_name, render_trigger("athar_truncate"))
              end
            end
            descriptors
          end
        end

        def build_descriptor(name, body)
          version = trigger_version_for(name, body)
          previous = previous_version_for(name)
          {
            name:,
            body:,
            version:,
            previous_version: previous,
            unchanged: !previous.nil? && version == previous
          }
        end

        def trigger_name
          "athar_on_#{table_name}"
        end

        def truncate_trigger_name
          "athar_truncate_on_#{table_name}"
        end

        def render_trigger(template_name)
          path = File.join(Athar::SQL::MODEL_TRIGGERS_DIR, "#{template_name}.sql.erb")
          template = File.read(path)
          locals = {
            schema_name:,
            table_name:,
            trigger_name:,
            truncate_trigger_name:,
            record_type:,
            primary_key:,
            id_type:,
            record_type_column_arg:,
            capture_mode:,
            columns_arg:
          }
          Athar::SQL.render(template, locals)
        end

        def trigger_sql
          render_trigger("athar_delete")
        end

        def truncate_trigger_sql
          render_trigger("athar_truncate")
        end

        def drop_trigger_sql
          [
            %(DROP TRIGGER IF EXISTS "#{trigger_name}" ON "#{schema_name}"."#{table_name}";),
            (track_truncate? ? %(DROP TRIGGER IF EXISTS "#{truncate_trigger_name}" ON "#{schema_name}"."#{table_name}";) : nil) # rubocop:disable Layout/LineLength
          ].compact.join("\n")
        end

        def triggers_destination
          File.expand_path("db/triggers", destination_root)
        end

        def trigger_version_for(target, body)
          previous = previous_version_for(target)
          return 1 if previous.nil?

          previous_path = File.join(triggers_destination, "#{target}_v#{previous.to_s.rjust(2, "0")}.sql")
          previous_body = File.exist?(previous_path) ? File.read(previous_path) : nil
          previous_body == body ? previous : previous + 1
        end

        def previous_version_for(target)
          return nil unless File.directory?(triggers_destination)

          Dir.entries(triggers_destination)
             .filter_map { |path| path[/\A#{Regexp.escape(target)}_v(\d+)\.sql\z/, 1]&.to_i }
             .max
        end

        def model_class
          @model_class ||= name.classify.constantize
        end

        def schema_name
          options[:schema] || schema_and_table_name.first || "public"
        end

        def table_name
          schema_and_table_name.last
        end

        def schema_and_table_name
          full = model_class.table_name.to_s
          @schema_and_table_name ||= full.include?(".") ? full.split(".", 2) : [nil, full]
        end

        def record_type
          options[:record_type] || model_class.base_class.name
        end

        def primary_key
          options[:primary_key] || model_class.primary_key.to_s
        end

        def id_type
          column = model_class.columns_hash[primary_key]
          raise_invalid("Primary key column #{primary_key.inspect} not found on #{table_name}") unless column

          sql_type = column.sql_type.to_s.downcase
          case sql_type
          when "bigint", "int8" then "bigint"
          when "integer", "int", "int4" then "integer"
          when "uuid" then "uuid"
          else
            raise_invalid("Unsupported primary key SQL type #{sql_type.inspect}; allowed: #{ALLOWED_ID_TYPES.inspect}")
          end
        end

        def record_type_column # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
          override = options[:record_type_column]
          if override.nil?
            inheritance = model_class.inheritance_column
            inheritance if model_class.columns_hash.key?(inheritance.to_s)
          elsif override.to_s == "false"
            nil
          else
            unless model_class.columns_hash.key?(override.to_s)
              raise_invalid("Record type column #{override.inspect} not found on #{table_name}")
            end
            override.to_s
          end
        end

        def record_type_column_arg
          rtc = record_type_column
          rtc ? "'#{rtc}'" : "'null'"
        end

        def capture_mode
          if options[:snapshot]
            "snapshot"
          elsif options[:only]
            "only"
          else
            "identity"
          end
        end

        def columns
          Array(options[:only]).flat_map { |item| item.to_s.split(",") }.map(&:strip).reject(&:empty?)
        end

        def columns_arg
          capture_mode == "only" ? "'{#{columns.join(",")}}'" : "'null'"
        end

        def migration_filename
          if remove?
            "athar_remove_#{table_name}_trigger"
          elsif update?
            # Fold the new version into the filename so consecutive --update
            # runs produce distinct files and Ruby constants.
            version = trigger_descriptors.map { |descriptor| descriptor[:version] }.max
            "athar_update_#{table_name}_trigger_v#{version.to_s.rjust(2, "0")}"
          else
            "athar_install_#{table_name}_trigger"
          end
        end

        def migration_class_name
          migration_filename.camelize
        end

        # The `on:` argument passed to Fx's create_trigger / update_trigger /
        # drop_trigger. For the public schema we keep the bare symbol so the
        # generated migration matches the Rails convention. For non-public
        # schemas we pass a "schema.table" string so DROP TRIGGER … ON … hits
        # the correct relation regardless of search_path.
        def fx_on_argument
          if schema_name == "public"
            ":#{table_name}"
          else
            %("#{schema_name}.#{table_name}")
          end
        end

        def track_truncate?
          options[:track_truncate]
        end

        def update?
          options[:update]
        end

        def remove?
          options[:remove]
        end
      end

      def self.next_migration_number(dir)
        ::ActiveRecord::Generators::Base.next_migration_number(dir)
      end

      private

      def validate_capture_mode!
        return unless options[:only] && options[:snapshot]

        raise_invalid("--only and --snapshot are mutually exclusive")
      end

      def validate_identifiers!
        validate_safe_identifier!("schema", schema_name)
        return if remove?

        validate_safe_identifier!("table", table_name)
        validate_safe_identifier!("primary_key", primary_key)
        validate_safe_class_name!("record_type", record_type)

        rtc_override = options[:record_type_column]
        return if rtc_override.nil? || rtc_override.to_s == "false"

        # Validate shape before record_type_column tries to look it up against
        # the model's columns; otherwise an unsafe value would surface as a
        # confusing "not found" error.
        validate_safe_identifier!("record_type_column", rtc_override)
      end

      def validate_safe_identifier!(label, value)
        return if value.to_s.match?(SAFE_IDENTIFIER_REGEX)

        raise_invalid("#{label} #{value.inspect} is not a safe SQL identifier; allowed: #{SAFE_IDENTIFIER_REGEX.source}") # rubocop:disable Layout/LineLength
      end

      def validate_safe_class_name!(label, value)
        return if value.to_s.match?(SAFE_CLASS_NAME_REGEX)

        raise_invalid("#{label} #{value.inspect} is not a safe Ruby class name")
      end

      def validate_id_type!
        return if remove?
        return if ALLOWED_ID_TYPES.include?(id_type)

        raise_invalid("id type must be one of #{ALLOWED_ID_TYPES.inspect}, got #{id_type.inspect}")
      end

      def validate_columns!
        return unless options[:only]

        columns.each do |column|
          if column.match?(UNSAFE_COLUMN_REGEX)
            raise_invalid("column name #{column.inspect} contains unsafe characters")
          end

          unless model_class.columns_hash.key?(column)
            raise_invalid("column #{column.inspect} not found on #{table_name}")
          end
        end
      end

      def raise_invalid(message)
        raise ::Thor::Error, "Athar generator error: #{message}"
      end
    end
  end
end
