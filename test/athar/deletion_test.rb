# frozen_string_literal: true

require "test_helper"

module Athar
  class DeletionTest < ActiveSupport::TestCase
    test "for_record(class, id) filters by record type and id" do
      user = User.create!(email: "1@example.com")
      user_id = user.id
      user.destroy!

      assert_equal 1, Deletion.for_record(User, user_id).count
      assert_equal 0, Deletion.for_record(User, user_id + 999).count
    end

    test "for_record(instance) filters before deletion" do
      user = User.create!(email: "i@example.com")
      Deletion.create!(
        record_type: "User",
        record_id: user.id,
        schema_name: "public",
        table_name: "users",
        deleted_at: Time.current,
        created_at: Time.current
      )

      assert_equal 1, Deletion.for_record(user).count
    end

    test "for_record requires id when class is passed" do
      error = assert_raises(ArgumentError) { Deletion.for_record(User) }

      assert_match(/id is required/, error.message)
    end

    test "for_record requires id when type is passed" do
      error = assert_raises(ArgumentError) { Deletion.for_record("User") }

      assert_match(/id is required/, error.message)
    end

    test "for_record_type filters" do
      User.create!(email: "rt@example.com").destroy!
      Account.create!(name: "X").destroy!

      assert_equal 1, Deletion.for_record_type("User").count
      assert_equal 1, Deletion.for_record_type("Account").count
    end

    test "for_table filters" do
      User.create!(email: "ft@example.com").destroy!

      assert_equal 1, Deletion.for_table("users").count
    end

    test "by_actor with model" do
      actor = ApiClient.create!(name: "operator")
      target = User.create!(email: "ba@example.com")

      Athar.with_actor(actor) { target.destroy! }

      assert_equal 1, Deletion.by_actor(actor).count
    end

    test "by_actor requires id when class is passed" do
      error = assert_raises(ArgumentError) { Deletion.by_actor(ApiClient) }

      assert_match(/id is required/, error.message)
    end

    test "by_actor requires id when type is passed" do
      error = assert_raises(ArgumentError) { Deletion.by_actor("ApiClient") }

      assert_match(/id is required/, error.message)
    end

    test "by_actor excludes symbolic actors stored only in metadata" do
      User.create!(email: "sym@example.com")

      Athar.with_metadata(actor: "cron") { User.delete_all }

      assert_equal 0, Deletion.by_actor("cron", 1).count
    end

    test "recent orders by deleted_at desc" do
      User.create!(email: "old@example.com").destroy!
      User.create!(email: "new@example.com").destroy!

      assert_operator Deletion.recent.first.deleted_at, :>=, Deletion.recent.last.deleted_at
    end

    test "before/after time scopes" do
      target = User.create!(email: "t@example.com")
      target.destroy!
      deletion = Deletion.last

      assert_includes Deletion.before(deletion.deleted_at + 1.minute), deletion
      assert_includes Deletion.after(deletion.deleted_at - 1.minute), deletion
    end

    test "actor returns nil when actor_type missing" do
      deletion = Deletion.create!(
        record_type: "User",
        record_id: 1,
        table_name: "users",
        deleted_at: Time.current,
        created_at: Time.current
      )

      assert_nil deletion.actor
    end

    test "actor returns nil when class can't be constantized" do
      deletion = Deletion.create!(
        record_type: "User",
        record_id: 1,
        actor_type: "NonExistentClass",
        actor_id: 1,
        table_name: "users",
        deleted_at: Time.current,
        created_at: Time.current
      )

      assert_nil deletion.actor
    end
  end
end
