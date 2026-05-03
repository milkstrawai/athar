# frozen_string_literal: true

require "rails/generators"
require "fileutils"
require "generators/athar/install/install_generator"
require "generators/athar/model/model_generator"

module Athar
  module TestSupport
    module DatabaseHelpers # rubocop:disable Metrics/ModuleLength
      DUMMY_ROOT = File.expand_path("../dummy", __dir__)
      MIGRATE_DIR = File.join(DUMMY_ROOT, "db", "migrate")
      FUNCTIONS_DIR = File.join(DUMMY_ROOT, "db", "functions")
      TRIGGERS_DIR = File.join(DUMMY_ROOT, "db", "triggers")
      TIMESTAMP_BASE = 20_260_101_000_000

      class << self # rubocop:disable Metrics/ClassLength
        def setup!
          bootstrap_database!
          rebuild_schema!
          prepare_dirs!
          run_app_schema_migration!
          run_install_migration!
          run_model_trigger_migrations!
          reset_models!
        end

        def bootstrap_database!
          ActiveRecord::Base.establish_connection
          ActiveRecord::Base.connection.execute("SELECT 1")
        end

        def rebuild_schema!
          connection = ActiveRecord::Base.connection
          connection.execute("DROP SCHEMA IF EXISTS reporting CASCADE")
          connection.execute("DROP TYPE IF EXISTS user_mood CASCADE")
          connection.execute("DROP SCHEMA IF EXISTS public CASCADE")
          connection.execute("CREATE SCHEMA public")
          connection.schema_cache.clear!
        end

        def prepare_dirs!
          [MIGRATE_DIR, FUNCTIONS_DIR, TRIGGERS_DIR].each do |dir|
            FileUtils.rm_rf(dir)
            FileUtils.mkdir_p(dir)
          end
          @timestamp = TIMESTAMP_BASE
        end

        def run_app_schema_migration!
          write_app_schema_migration!
          migrate!
        end

        def run_install_migration!
          runner = Athar::Generators::InstallGenerator.new([], install_options)
          runner.destination_root = DUMMY_ROOT
          runner.send(:validate_options!)
          runner.send(:write_function_files) if fx_mode?

          rendered = render_template(runner, install_template_name)
          rendered = rendered.sub(/\Aclass\s+\w+/, "class AtharInstall")
          stamp_and_write("athar_install") { rendered }
          migrate!
        end

        def run_model_trigger_migrations!
          register_model_trigger("User", only: %w[email name tags preferences status mood handle created_at])
          register_model_trigger("Account", snapshot: true)
          register_model_trigger("ApiClient")
          register_model_trigger("UuidWidget")
          register_model_trigger("SessionRecord", track_truncate: true)
          register_model_trigger("Comment", track_truncate: true)
          register_model_trigger("LegacyToken", record_type_column: "false")
          register_model_trigger("Reporting::Bucket", schema: "reporting")
          register_model_trigger("SmallCounter", snapshot: true)
          migrate!
        end

        def reset_models!
          ActiveRecord::Base.descendants.each do |klass|
            klass.reset_column_information if klass.respond_to?(:reset_column_information)
          end
        end

        def install_options
          opts = {}
          opts[:fx] = false unless fx_mode?
          opts
        end

        def install_template_name
          fx_mode? ? "install_migration_fx.rb.erb" : "install_migration.rb.erb"
        end

        def model_template_name
          fx_mode? ? "migration_fx.rb.erb" : "migration.rb.erb"
        end

        def migrate!
          ActiveRecord::Base.connection.schema_cache.clear!
          context = ActiveRecord::MigrationContext.new(MIGRATE_DIR)
          ActiveRecord::Migration.suppress_messages do
            context.migrate
          end
        end

        def reset_audit_tables!
          ActiveRecord::Base.connection.execute(
            "TRUNCATE athar_deletions, athar_table_events RESTART IDENTITY"
          )
        end

        def trigger_exists?(table_name, trigger_name)
          result = ActiveRecord::Base.connection.select_value(
            ActiveRecord::Base.sanitize_sql_array([
                                                    "SELECT 1 FROM pg_trigger " \
                                                    "JOIN pg_class ON pg_trigger.tgrelid = pg_class.oid " \
                                                    "WHERE pg_class.relname = ? AND pg_trigger.tgname = ? LIMIT 1",
                                                    table_name, trigger_name
                                                  ])
          )
          !result.nil?
        end

        def function_exists?(function_name)
          result = ActiveRecord::Base.connection.select_value(
            ActiveRecord::Base.sanitize_sql_array([
                                                    "SELECT 1 FROM pg_proc WHERE proname = ? LIMIT 1",
                                                    function_name
                                                  ])
          )
          !result.nil?
        end

        def write_app_schema_migration!
          stamp_and_write("athar_test_app_schema") do
            <<~MIGRATION
              class AtharTestAppSchema < ActiveRecord::Migration[#{ActiveRecord::Migration.current_version}]
                def up
                  enable_extension "pgcrypto"
                  enable_extension "citext"

                  execute "CREATE SCHEMA IF NOT EXISTS reporting"
                  execute "CREATE TYPE user_mood AS ENUM ('curious', 'grumpy', 'serene')"

                  create_table :accounts do |t|
                    t.string :name
                    t.timestamps
                  end

                  create_table :users do |t|
                    t.references :account, foreign_key: false
                    t.string :type
                    t.string :email
                    t.string :name
                    t.string :token
                    t.boolean :active, default: true
                    t.string :status
                    t.string :tags, array: true, default: []
                    t.jsonb :preferences, default: {}
                    t.column :mood, :user_mood
                    t.column :handle, :citext
                    t.timestamps
                  end

                  create_table :sessions do |t|
                    t.references :user, foreign_key: false
                    t.string :token
                    t.timestamps
                  end

                  create_table :api_clients do |t|
                    t.string :name
                    t.timestamps
                  end

                  create_table :uuid_widgets, id: :uuid do |t|
                    t.string :label
                    t.timestamps
                  end

                  # User comments — used for DB-level ON DELETE CASCADE.
                  create_table :comments do |t|
                    t.bigint :user_id, null: false
                    t.string :body
                    t.timestamps
                  end
                  execute <<~SQL
                    ALTER TABLE comments
                    ADD CONSTRAINT comments_user_id_fkey
                    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
                  SQL

                  create_table :legacy_tokens do |t|
                    t.string :type
                    t.string :body
                    t.timestamps
                  end

                  create_table :reporting_buckets, id: :integer do |t|
                    t.string :name
                    t.timestamps
                  end
                  execute "ALTER TABLE reporting_buckets SET SCHEMA reporting"

                  create_table :small_counters, id: :integer do |t|
                    t.string :name
                    t.integer :value, default: 0
                    t.timestamps
                  end
                end
              end
            MIGRATION
          end
        end

        def register_model_trigger(model_name, options = {}) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength
          opts = { schema: options[:schema] || "public" }
          opts[:fx] = false unless fx_mode?
          opts[:only] = options[:only] if options[:only]
          opts[:snapshot] = options[:snapshot] if options[:snapshot]
          opts[:track_truncate] = options[:track_truncate] if options[:track_truncate]
          opts[:record_type_column] = options[:record_type_column] if options.key?(:record_type_column)

          generator = Athar::Generators::ModelGenerator.new([model_name], opts)
          generator.destination_root = DUMMY_ROOT
          generator.send(:validate_options!)
          generator.send(:write_trigger_files) if fx_mode?

          rendered = render_template(generator, model_template_name)
          klass_name = "AtharTrigger#{generator.send(:table_name).camelize}"
          rendered = rendered.sub(/\Aclass\s+\w+/, "class #{klass_name}")
          stamp_and_write("athar_trigger_#{generator.send(:table_name)}") { rendered }
        end

        def render_template(generator, template_name)
          template_dir = generator.class.source_root
          source = File.read(File.join(template_dir, template_name))
          ERB.new(source, trim_mode: "-").result(generator.instance_eval { binding })
        end

        def stamp_and_write(name)
          @timestamp ||= TIMESTAMP_BASE
          @timestamp += 1
          path = File.join(MIGRATE_DIR, "#{@timestamp}_#{name}.rb")
          File.write(path, yield)
          path
        end

        def fx_mode?
          ENV["ATHAR_NO_FX"] != "1"
        end
      end

      def reset_audit_tables! = DatabaseHelpers.reset_audit_tables!

      def trigger_exists?(table_name, trigger_name)
        DatabaseHelpers.trigger_exists?(table_name, trigger_name)
      end

      def function_exists?(function_name)
        DatabaseHelpers.function_exists?(function_name)
      end
    end
  end
end
