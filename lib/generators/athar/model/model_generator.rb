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
      BUILTIN_MASKS = %w[email partial hash].freeze
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
      class_option :mask, type: :array, default: nil, desc: "Mask spec: col:mask_name[:arg1:arg2],..."

      def validate_options!
        validate_capture_mode!
        validate_identifiers!
        validate_id_type!
        validate_columns!
        validate_masks!
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
            columns_arg:,
            masks_arg:
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
          @schema_and_table_name ||= begin
            full = remove? ? infer_table_name : model_class.table_name.to_s
            full.include?(".") ? full.split(".", 2) : [nil, full]
          end
        end

        def infer_table_name
          name.classify.constantize.table_name.to_s
        rescue NameError
          name.tableize
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
          rtc ? "'#{rtc}'" : "'__athar_none__'"
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
          capture_mode == "only" ? "'{#{columns.join(",")}}'" : "'__athar_none__'"
        end

        def masks_arg
          return "'__athar_none__'" if mask_specs.empty?

          literals = mask_specs.map do |spec|
            pieces = [spec[:column], spec[:mask], *spec[:args]]
            %("#{pieces.join(":")}")
          end

          "'{#{literals.join(",")}}'"
        end

        def mask_specs
          @mask_specs ||= Array(options[:mask]).flat_map { |item| item.to_s.split(",") }
                                               .map(&:strip).reject(&:empty?)
                                               .map { |spec| parse_mask_spec(spec) }
        end

        def parse_mask_spec(spec)
          parts = spec.split(":")
          raise_invalid("Mask spec #{spec.inspect} is missing a mask name") if parts.length < 2
          { column: parts[0], mask: parts[1], args: parts[2..] || [] }
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
        # schemas we pass a "schema.table" string so DROP TRIGGER ... ON ... hits
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
        return if remove?

        validate_safe_identifier!("schema", schema_name)
        validate_safe_identifier!("table", table_name)
        validate_safe_identifier!("primary_key", primary_key)
        validate_safe_class_name!("record_type", record_type)

        rtc_override = options[:record_type_column]
        return if rtc_override.nil? || rtc_override.to_s == "false"

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

      def validate_masks! # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength,Metrics/PerceivedComplexity
        return if options[:mask].nil? || options[:mask].empty?

        raise_invalid("--mask requires --only or --snapshot") unless options[:only] || options[:snapshot]

        seen_columns = {}
        mask_specs.each do |spec|
          column = spec[:column]
          mask = spec[:mask]
          args = spec[:args]

          validate_safe_identifier!("column", column)
          validate_safe_identifier!("mask", mask)

          raise_invalid("Duplicate column #{column.inspect} in --mask") if seen_columns[column]
          seen_columns[column] = true

          if options[:only] && !columns.include?(column)
            raise_invalid("Mask references uncaptured column #{column.inspect}; add it to --only or use --snapshot")
          end

          if options[:snapshot] && !model_class.columns_hash.key?(column)
            raise_invalid("Mask references unknown column #{column.inspect} on #{table_name}")
          end

          validate_mask_arity!(mask, args)
          validate_mask_resolves!(mask)
        end
      end

      def validate_mask_arity!(mask, args) # rubocop:disable Metrics/CyclomaticComplexity
        case mask
        when "email", "hash"
          raise_invalid("#{mask} takes no arguments (got #{args.length})") unless args.empty?
        when "partial"
          unless args.length == 2 && args.all? { |a| a.match?(/\A\d+\z/) }
            raise_invalid("partial requires exactly 2 integer args (got #{args.inspect})")
          end
        else
          raise_invalid("#{mask} is a custom mask and takes no arguments (got #{args.inspect})") unless args.empty?
        end
      end

      def validate_mask_resolves!(mask)
        return if BUILTIN_MASKS.include?(mask)
        return if custom_mask_installed?(mask)

        raise_invalid(
          "Mask :#{mask} is not installed. Run 'bin/rails g athar:mask #{mask} --regex=...' " \
          "or install a custom athar_mask_#{mask}(jsonb) function first."
        )
      end

      def custom_mask_installed?(mask)
        custom_mask_file_installed?(mask) || custom_mask_database_installed?(mask)
      end

      def custom_mask_file_installed?(mask)
        return false unless fx?

        Dir.glob(File.join(destination_root, "db/functions/athar_mask_#{mask}_v*.sql")).any?
      end

      def custom_mask_database_installed?(mask)
        sql = ActiveRecord::Base.sanitize_sql_array([
                                                      <<~SQL.squish,
                                                        SELECT 1
                                                        FROM pg_proc p
                                                        WHERE p.proname = ?
                                                          AND p.pronargs = 1
                                                          AND p.proargtypes[0] = 'jsonb'::regtype
                                                          AND p.prorettype = 'jsonb'::regtype
                                                          AND pg_function_is_visible(p.oid)
                                                        LIMIT 1
                                                      SQL
                                                      "athar_mask_#{mask}"
                                                    ])

        !ActiveRecord::Base.connection.select_value(sql).nil?
      rescue StandardError
        # If we can't reach the DB, fall back to false. The trigger install
        # itself will fail loudly later if the function truly doesn't exist.
        false
      end

      def raise_invalid(message)
        raise Athar::GeneratorError, "Athar generator error: #{message}"
      end
    end
  end
end
