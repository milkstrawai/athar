# frozen_string_literal: true

require "test_helper"

module Athar
  class StiTest < ActiveSupport::TestCase
    test "STI null type falls back to base record type" do
      ActiveRecord::Base.connection.execute(
        "INSERT INTO users (email, name, type, created_at, updated_at) " \
        "VALUES ('null-sti@example.com', 'Plain', NULL, now(), now())"
      )

      user_id = ActiveRecord::Base.connection.select_value(
        "SELECT id FROM users WHERE email = 'null-sti@example.com'"
      )

      ActiveRecord::Base.connection.execute("DELETE FROM users WHERE id = #{user_id}")

      assert_equal "User", Athar::Deletion.last.record_type
    end

    test "unknown STI type strings are stored as-is without raising" do
      ActiveRecord::Base.connection.execute(
        "INSERT INTO users (email, name, type, created_at, updated_at) " \
        "VALUES ('weird-sti@example.com', 'Weird', 'NotARealClass', now(), now())"
      )
      user_id = ActiveRecord::Base.connection.select_value(
        "SELECT id FROM users WHERE email = 'weird-sti@example.com'"
      )

      assert_nothing_raised do
        ActiveRecord::Base.connection.execute("DELETE FROM users WHERE id = #{user_id}")
      end

      assert_equal "NotARealClass", Athar::Deletion.last.record_type
    end

    test "for_record finds an STI subclass deletion through either class" do
      admin = Admin.create!(email: "sti-find@example.com", name: "Boss")
      admin_id = admin.id
      admin.destroy!

      assert_equal 1, Athar::Deletion.for_record(Admin, admin_id).count
      assert_equal 1, Athar::Deletion.for_record(User, admin_id).count
    end

    test "--record-type-column=false stores the base class even when type is set" do
      LegacyToken.connection.execute(
        "INSERT INTO legacy_tokens (type, body, created_at, updated_at) " \
        "VALUES ('SomeOtherClass', 'tk', now(), now())"
      )
      token_id = LegacyToken.connection.select_value(
        "SELECT id FROM legacy_tokens WHERE body = 'tk'"
      )

      LegacyToken.connection.execute("DELETE FROM legacy_tokens WHERE id = #{token_id}")

      assert_equal "LegacyToken", Athar::Deletion.last.record_type
    end
  end
end
