# frozen_string_literal: true

require "test_helper"

module Athar
  class DeleteSourcesTest < ActiveSupport::TestCase
    test "single-row #delete (no callbacks) is captured" do
      user = User.create!(email: "skip-callbacks@example.com")

      assert_difference "Athar::Deletion.count", 1 do
        user.delete
      end

      assert_equal user.id, Athar::Deletion.last.record_id
    end

    test "DB-level ON DELETE CASCADE captures child rows on triggered tables" do
      user = User.create!(email: "cascade@example.com")
      Comment.create!(user_id: user.id, body: "first")
      Comment.create!(user_id: user.id, body: "second")

      assert_difference "Athar::Deletion.where(table_name: 'comments').count" => 2,
                        "Athar::Deletion.where(table_name: 'users').count" => 1 do
        ActiveRecord::Base.connection.execute("DELETE FROM users WHERE id = #{user.id}")
      end
    end
  end
end
