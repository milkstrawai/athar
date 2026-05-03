# frozen_string_literal: true

require "test_helper"

module Athar
  class PostgresSurfaceTest < ActiveSupport::TestCase
    test "captures deletes from a non-public schema" do
      bucket = Reporting::Bucket.create!(name: "weekly")

      assert_difference "Athar::Deletion.count", 1 do
        bucket.destroy!
      end

      deletion = Athar::Deletion.last

      assert_equal "reporting", deletion.schema_name
      assert_equal "reporting_buckets", deletion.table_name
      assert_equal "Reporting::Bucket", deletion.record_type
    end

    test "for_record finds non-public schema deletions through the model class" do
      bucket = Reporting::Bucket.create!(name: "lookup")
      bucket_id = bucket.id
      bucket.destroy!

      assert_equal 1, Athar::Deletion.for_record(Reporting::Bucket, bucket_id).count
    end

    test "integer primary key model is captured" do
      counter = SmallCounter.create!(id: 7, name: "alpha", value: 3)

      assert_difference "Athar::Deletion.count", 1 do
        counter.destroy!
      end

      deletion = Athar::Deletion.last

      assert_equal 7, deletion.record_id
      assert_equal "SmallCounter", deletion.record_type
    end

    test "enum, citext, array and nested jsonb columns survive snapshot" do
      user = User.create!(
        email: "kinds@example.com",
        name: "K",
        status: "vip",
        mood: "curious",
        handle: "Curious-One",
        tags: %w[alpha beta],
        preferences: { theme: "dark", widgets: [1, 2] }
      )

      user.destroy!

      data = Athar::Deletion.last.record_data

      assert_equal "curious", data["mood"], "enum should be stored as string"
      assert_equal "Curious-One", data["handle"], "citext should be stored as string"
      assert_equal %w[alpha beta], data["tags"], "array column should be stored as array"
      assert_equal({ "theme" => "dark", "widgets" => [1, 2] }, data["preferences"])
    end

    test "timestamp columns are stored as ISO 8601 strings" do
      user = User.create!(email: "ts@example.com", name: "Ts")
      user.destroy!

      data = Athar::Deletion.last.record_data

      assert_kind_of String, data["created_at"]
      assert_match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/, data["created_at"])
    end
  end
end
