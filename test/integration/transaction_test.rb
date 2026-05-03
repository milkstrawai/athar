# frozen_string_literal: true

require "test_helper"

module Athar
  class TransactionTest < ActiveSupport::TestCase
    test "savepoint rollback removes inner audit rows but keeps outer" do
      outer = User.create!(email: "outer@example.com")
      inner = User.create!(email: "inner@example.com")

      ActiveRecord::Base.transaction do
        outer.destroy!

        assert_no_difference "Athar::Deletion.where(record_id: inner.id).count" do
          ActiveRecord::Base.transaction(requires_new: true) do
            inner.destroy!
            raise ActiveRecord::Rollback
          end
        end

        assert_equal 1, Deletion.where(record_id: outer.id).count
      end
    end

    test "metadata visible inside transaction does not leak after" do
      Athar.with_metadata(scope: "txn") do
        assert_equal({ "scope" => "txn" }, MetadataStack.current)
      end

      assert_equal({}, MetadataStack.current)
    end
  end
end
