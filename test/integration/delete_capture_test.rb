# frozen_string_literal: true

require "test_helper"

module Athar
  class DeleteCaptureTest < ActiveSupport::TestCase # rubocop:disable Metrics/ClassLength
    test "captures destroy with --only filter" do
      user = User.create!(email: "a@example.com", name: "Ali", token: "secret", status: "active")

      assert_difference "Athar::Deletion.count", 1 do
        user.destroy!
      end

      deletion = Athar::Deletion.last

      assert_equal "User", deletion.record_type
      assert_equal user.id, deletion.record_id
      assert_equal "users", deletion.table_name
      assert_equal "public", deletion.schema_name
      assert_equal "a@example.com", deletion.record_data["email"]
      assert_equal "Ali", deletion.record_data["name"]
      assert_equal "active", deletion.record_data["status"]
      assert_equal [], deletion.record_data["tags"]
      assert_equal({}, deletion.record_data["preferences"])
      refute deletion.record_data.key?("token")
    end

    test "captures full snapshot for snapshot mode" do
      account = Account.create!(name: "Acme")

      account.destroy!

      deletion = Athar::Deletion.last

      assert_equal "Account", deletion.record_type
      assert_equal account.id, deletion.record_data["id"]
      assert_equal "Acme", deletion.record_data["name"]
    end

    test "captures identity-only when no --only or --snapshot" do
      client = ApiClient.create!(name: "service-X")

      client.destroy!

      deletion = Athar::Deletion.last

      assert_equal "ApiClient", deletion.record_type
      assert_equal({}, deletion.record_data)
    end

    test "delete_all captures one row per deleted record" do
      User.create!(email: "a@example.com")
      User.create!(email: "b@example.com")
      User.create!(email: "c@example.com")

      assert_difference "Athar::Deletion.count", 3 do
        User.delete_all
      end
    end

    test "raw SQL DELETE captured" do
      user = User.create!(email: "raw@example.com")

      assert_difference "Athar::Deletion.count", 1 do
        ActiveRecord::Base.connection.execute("DELETE FROM users WHERE id = #{user.id}")
      end

      assert_equal user.id, Athar::Deletion.last.record_id
    end

    test "rolled-back transaction creates no audit row" do
      User.create!(email: "rb@example.com")

      assert_no_difference "Athar::Deletion.count" do
        ActiveRecord::Base.transaction do
          User.delete_all
          raise ActiveRecord::Rollback
        end
      end
    end

    test "without_capture suppresses audit row" do
      User.create!(email: "noaudit@example.com")

      assert_no_difference "Athar::Deletion.count" do
        Athar.without_capture do
          User.delete_all
        end
      end
    end

    test "STI concrete class is captured" do
      admin = Admin.create!(email: "admin@example.com", name: "Boss")

      admin.destroy!

      assert_equal "Admin", Athar::Deletion.last.record_type
    end

    test "with_actor records actor on the deletion" do
      actor = ApiClient.create!(name: "deleter")
      target = User.create!(email: "victim@example.com")

      Athar.with_actor(actor) do
        target.destroy!
      end

      deletion = Athar::Deletion.last

      assert_equal "ApiClient", deletion.actor_type
      assert_equal actor.id, deletion.actor_id
    end

    test "with_metadata records metadata" do
      target = User.create!(email: "meta@example.com")

      Athar.with_metadata(reason: "GDPR", request_id: "req-1") do
        target.destroy!
      end

      meta = Athar::Deletion.last.metadata

      assert_equal "GDPR", meta["reason"]
      assert_equal "req-1", meta["request_id"]
    end

    test "with_actor symbol raises ArgumentError" do
      assert_raises(ArgumentError) do
        Athar.with_actor("cron") {} # rubocop:disable Lint/EmptyBlock
      end
    end

    test "symbolic actor goes in metadata" do
      User.create!(email: "sym@example.com")

      Athar.with_metadata(actor: "cron", reason: "cleanup") do
        User.delete_all
      end

      meta = Athar::Deletion.last.metadata

      assert_equal "cron", meta["actor"]
      assert_equal "cleanup", meta["reason"]
      assert_nil Athar::Deletion.last.actor_type
    end

    test "nested metadata merges and inner overrides outer" do
      User.create!(email: "nest@example.com")

      Athar.with_metadata(reason: "outer", source: "web") do
        Athar.with_metadata(source: "admin") do
          User.delete_all
        end
      end

      meta = Athar::Deletion.last.metadata

      assert_equal "outer", meta["reason"]
      assert_equal "admin", meta["source"]
    end

    test "metadata does not leak after the block" do
      Athar.with_metadata(scoped: "yes") do
        # within the block
      end

      User.create!(email: "leak@example.com").destroy!

      meta = Athar::Deletion.last.metadata

      refute meta.key?("scoped"), "metadata leaked after block"
    end

    test "truncate trigger records a table event" do
      SessionRecord.create!(token: "abc")

      assert_difference "Athar::TableEvent.truncate.count", 1 do
        ActiveRecord::Base.connection.execute("TRUNCATE TABLE sessions")
      end

      event = Athar::TableEvent.truncate.last

      assert_equal "sessions", event.table_name
      assert_equal "public", event.schema_name
    end

    test "delete record captures with deleted_at and created_at" do
      target = User.create!(email: "ts@example.com")

      target.destroy!

      deletion = Athar::Deletion.last

      assert deletion.deleted_at
      assert deletion.created_at
    end

    test "for_record scope returns matching deletions" do
      target = User.create!(email: "fr@example.com")
      target_id = target.id
      target.destroy!

      assert_equal 1, Athar::Deletion.for_record(User, target_id).count
    end

    test "actor lookup tolerates renamed class" do
      actor = ApiClient.create!(name: "byebye")
      target = User.create!(email: "byebye@example.com")

      Athar.with_actor(actor) { target.destroy! }
      deletion = Athar::Deletion.last

      Object.send(:remove_const, :ApiClient) if Object.const_defined?(:ApiClient)

      assert_nil deletion.actor
    ensure
      load File.expand_path("../dummy/app/models/api_client.rb", __dir__)
    end

    test "invalid actor id raises and rolls back delete" do
      user = User.create!(email: "boom@example.com")

      assert_raises(ActiveRecord::StatementInvalid) do
        ActiveRecord::Base.transaction do
          ActiveRecord::Base.connection.execute(
            "SET LOCAL athar.meta = '{\"actor_type\":\"X\",\"actor_id\":\"not-a-bigint\"}'"
          )
          user.destroy!
        end
      end

      assert User.exists?(user.id), "delete should roll back when trigger insert fails"
    end
  end
end
