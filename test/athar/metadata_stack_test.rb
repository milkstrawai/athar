# frozen_string_literal: true

require "test_helper"

module Athar
  class MetadataStackTest < ActiveSupport::TestCase
    setup do
      MetadataStack.clear!
    end

    teardown do
      MetadataStack.clear!
    end

    test "current is empty by default" do
      assert_equal({}, MetadataStack.current)
    end

    test "push returns merged metadata" do
      result = MetadataStack.push("reason" => "test")

      assert_equal({ "reason" => "test" }, result)
    end

    test "current is cached after push" do
      MetadataStack.push("a" => "1")
      # Second call should return cached value, not rebuild
      assert_equal({ "a" => "1" }, MetadataStack.current)
    end

    test "nested pushes merge correctly" do
      MetadataStack.push("a" => "1", "b" => "2")
      MetadataStack.push("b" => "3", "c" => "4")

      assert_equal({ "a" => "1", "b" => "3", "c" => "4" }, MetadataStack.current)
    end

    test "pop invalidates cache" do
      MetadataStack.push("a" => "1")
      MetadataStack.push("b" => "2")
      MetadataStack.pop

      assert_equal({ "a" => "1" }, MetadataStack.current)
    end

    test "clear! empties the stack" do
      MetadataStack.push("a" => "1")
      MetadataStack.clear!

      assert_equal({}, MetadataStack.current)
    end

    test "clear! invalidates cache" do
      MetadataStack.push("a" => "1")
      MetadataStack.clear!

      assert_equal({}, MetadataStack.current)
    end
  end
end
