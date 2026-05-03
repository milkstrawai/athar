# frozen_string_literal: true

require "test_helper"

module Athar
  class CascadeTest < ActiveSupport::TestCase
    test "Rails dependent: :destroy cascades to triggered child tables" do
      user = User.create!(email: "p@example.com")
      SessionRecord.create!(user_id: user.id, token: "s1")
      SessionRecord.create!(user_id: user.id, token: "s2")

      assert_difference -> { Deletion.count } => 3 do
        user.destroy!
      end

      assert_equal 2, Deletion.for_table("sessions").count
      assert_equal 1, Deletion.for_table("users").count
    end

    test "delete_all on parent cascades only when triggered" do
      account = Account.create!(name: "Big")
      User.create!(email: "u1@example.com", account_id: account.id)
      User.create!(email: "u2@example.com", account_id: account.id)

      assert_difference "Deletion.count", 3 do
        account.destroy!
      end
    end

    test "TRUNCATE parent CASCADE records one event per truncated child with tracking" do
      user = User.create!(email: "p-trunc@example.com")
      Comment.create!(user_id: user.id, body: "doomed")

      # comments has a truncate trigger and a FK to users — TRUNCATE users
      # CASCADE truncates comments transitively.
      assert_difference "Athar::TableEvent.truncate.where(table_name: 'comments').count", 1 do
        ActiveRecord::Base.connection.execute("TRUNCATE TABLE users CASCADE")
      end
    end

    test "truncate event rolls back with the surrounding transaction" do
      SessionRecord.create!(token: "rollback-trunc")

      assert_no_difference "Athar::TableEvent.truncate.count" do
        ActiveRecord::Base.transaction do
          ActiveRecord::Base.connection.execute("TRUNCATE TABLE sessions")
          raise ActiveRecord::Rollback
        end
      end
    end
  end
end
