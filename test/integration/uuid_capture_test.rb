# frozen_string_literal: true

require "test_helper"

module Athar
  class UuidCaptureTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    UUID_DB_NAME = "athar_uuid_test"

    teardown do
      ensure_main_connection_clean!
    end

    class UuidPost < ActiveRecord::Base
      self.table_name = "uuid_posts"
    end

    class UuidActor < ActiveRecord::Base
      self.table_name = "uuid_actors"
    end

    class UuidDeletion < ActiveRecord::Base
      self.table_name = "athar_deletions"
    end

    setup do
      @main_config = ActiveRecord::Base.connection_db_config

      ActiveRecord::Base.establish_connection(
        adapter: "postgresql",
        host: ENV.fetch("ATHAR_DB_HOST", "localhost"),
        port: ENV.fetch("ATHAR_DB_PORT", 5434),
        username: ENV.fetch("ATHAR_DB_USER", "athar"),
        password: ENV.fetch("ATHAR_DB_PASSWORD", "athar"),
        database: UUID_DB_NAME
      )

      build_uuid_schema!
    end

    teardown do
      ActiveRecord::Base.establish_connection(@main_config)
    end

    test "captures UUID primary key delete" do
      post_id = UuidPost.create!(title: "T").id

      UuidPost.find(post_id).destroy!

      deletion = UuidDeletion.last

      assert_equal post_id, deletion.record_id
      assert_equal "UuidPost", deletion.record_type
    end

    test "captures UUID actor" do
      actor_id = UuidActor.create!(name: "actor").id
      target_id = UuidPost.create!(title: "actor-test").id

      Athar.with_metadata(actor_type: "UuidActor", actor_id: actor_id) do
        UuidPost.find(target_id).destroy!
      end

      deletion = UuidDeletion.last

      assert_equal "UuidActor", deletion.actor_type
      assert_equal actor_id, deletion.actor_id
    end

    test "invalid UUID actor id fails delete" do
      target_id = UuidPost.create!(title: "fail").id

      assert_raises(ActiveRecord::StatementInvalid) do
        ActiveRecord::Base.transaction do
          ActiveRecord::Base.connection.execute(
            "SET LOCAL athar.meta = '{\"actor_type\":\"UuidActor\",\"actor_id\":\"not-a-uuid\"}'"
          )
          UuidPost.find(target_id).destroy!
        end
      end

      assert_predicate UuidPost.where(id: target_id), :exists?
    end

    private

    def build_uuid_schema!
      conn = ActiveRecord::Base.connection
      conn.execute("DROP SCHEMA IF EXISTS public CASCADE")
      conn.execute("CREATE SCHEMA public")
      conn.execute("CREATE EXTENSION IF NOT EXISTS pgcrypto")

      conn.execute(<<~SQL)
        CREATE TABLE uuid_posts (
          id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
          title text,
          created_at timestamp DEFAULT statement_timestamp()
        );

        CREATE TABLE uuid_actors (
          id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
          name text
        );

        CREATE TABLE athar_deletions (
          id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
          record_type text NOT NULL,
          record_id uuid NOT NULL,
          actor_type text,
          actor_id uuid,
          schema_name text,
          table_name text NOT NULL,
          deleted_at timestamp NOT NULL,
          created_at timestamp NOT NULL,
          record_data jsonb DEFAULT '{}'::jsonb NOT NULL,
          metadata jsonb DEFAULT '{}'::jsonb NOT NULL
        );

        CREATE TABLE athar_table_events (
          id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
          event_type text NOT NULL,
          schema_name text,
          table_name text NOT NULL,
          actor_type text,
          actor_id uuid,
          metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
          occurred_at timestamp NOT NULL,
          created_at timestamp NOT NULL
        );
      SQL

      Athar::SQL.all_functions(foreign_key_type: "uuid").each_value do |body|
        conn.execute(body)
      end

      conn.execute(<<~SQL)
        CREATE TRIGGER athar_on_uuid_posts
        BEFORE DELETE ON uuid_posts
        FOR EACH ROW
        WHEN (coalesce(current_setting('athar.disabled', true), '') <> 'on')
        EXECUTE PROCEDURE athar_capture_delete(
          'UuidPost', 'public', 'uuid_posts', 'id', 'uuid', '__athar_none__',
          'identity', '__athar_none__', '__athar_none__'
        );
      SQL

      [UuidPost, UuidActor, UuidDeletion].each(&:reset_column_information)
    end

    def ensure_main_connection_clean!
      ActiveRecord::Base.establish_connection(@main_config)
      ActiveRecord::Base.connection.execute("TRUNCATE athar_deletions, athar_table_events RESTART IDENTITY")
    end
  end
end
