# frozen_string_literal: true

require "test_helper"

module Athar
  class ContextTest < ActiveSupport::TestCase
    test "with_actor accepts ActiveRecord instance" do
      actor = ApiClient.create!(name: "ctx")

      Athar.with_actor(actor) do
        # noop
      end

      assert_equal({}, MetadataStack.current)
    end

    test "with_actor(nil) yields without setting actor" do
      called = false
      Athar.with_actor(nil) { called = true }

      assert called
    end

    test "with_actor(string) raises ArgumentError" do
      assert_raises(ArgumentError) do
        Athar.with_actor("cron") {} # rubocop:disable Lint/EmptyBlock
      end
    end

    test "with_metadata pushes and pops the stack" do
      Athar.with_metadata(reason: "outer") do
        assert_equal({ "reason" => "outer" }, MetadataStack.current)
      end

      assert_equal({}, MetadataStack.current)
    end

    test "with_metadata nests and merges" do
      Athar.with_metadata(reason: "outer", source: "web") do
        Athar.with_metadata(source: "admin") do
          merged = MetadataStack.current

          assert_equal "outer", merged["reason"]
          assert_equal "admin", merged["source"]
        end

        assert_equal "web", MetadataStack.current["source"]
      end
    end

    test "with_context accepts actor and metadata" do
      actor = ApiClient.create!(name: "with_ctx")

      Athar.with_context(actor: actor, reason: "GDPR") do
        meta = MetadataStack.current

        assert_equal "ApiClient", meta["actor_type"]
        assert_equal actor.id, meta["actor_id"]
        assert_equal "GDPR", meta["reason"]
      end

      assert_equal({}, MetadataStack.current)
    end

    test "without_capture suppresses delete capture" do
      User.create!(email: "wc@example.com")

      assert_no_difference "Athar::Deletion.count" do
        Athar.without_capture do
          User.delete_all
        end
      end
    end

    test "without_capture restores capture after block" do
      Athar.without_capture do
        # noop
      end

      User.create!(email: "after@example.com")

      assert_difference "Athar::Deletion.count", 1 do
        User.delete_all
      end
    end

    test "nested without_capture keeps capture suppressed in outer block" do
      User.create!(email: "outer@example.com")
      User.create!(email: "inner@example.com")

      assert_no_difference "Athar::Deletion.count" do
        Athar.without_capture do
          Athar.without_capture do
            User.where(email: "inner@example.com").delete_all
          end

          # Still inside the outer without_capture — capture must stay off.
          User.where(email: "outer@example.com").delete_all
        end
      end
    end

    test "metadata is restored when the block raises" do
      assert_raises(RuntimeError) do
        Athar.with_metadata(reason: "outer") do
          Athar.with_metadata(source: "inner") do
            raise "boom"
          end
        end
      end

      assert_equal({}, MetadataStack.current)
    end

    test "metadata is restored after a savepoint rollback" do
      Athar.with_metadata(reason: "outer") do
        outer_meta = MetadataStack.current.dup
        ActiveRecord::Base.transaction(requires_new: true) do
          Athar.with_metadata(source: "inner") do
            assert_equal "inner", MetadataStack.current["source"]
          end
          raise ActiveRecord::Rollback
        end

        assert_equal outer_meta, MetadataStack.current
      end

      assert_equal({}, MetadataStack.current)
    end
  end
end
