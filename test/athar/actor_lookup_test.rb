# frozen_string_literal: true

require "test_helper"

module Athar
  class ActorLookupTest < ActiveSupport::TestCase
    test "actor is memoized on repeated access" do
      actor = ApiClient.create!(name: "memo")
      user = User.create!(email: "memo@example.com")

      Athar.with_actor(actor) { user.destroy! }
      deletion = Deletion.last

      first = deletion.actor
      second = deletion.actor

      assert_same first, second
      assert_equal actor, first
    end

    test "for_records preloads actors" do
      actor1 = ApiClient.create!(name: "a1")
      actor2 = ApiClient.create!(name: "a2")
      user1 = User.create!(email: "u1@example.com")
      user2 = User.create!(email: "u2@example.com")

      Athar.with_actor(actor1) { user1.destroy! }
      Athar.with_actor(actor2) { user2.destroy! }

      deletions = Deletion.last(2)
      Deletion.for_records(deletions)

      # After for_records, actor should be memoized without hitting DB
      assert_equal actor1, deletions[0].actor
      assert_equal actor2, deletions[1].actor
    end

    test "actor returns nil when actor_type is blank" do
      user = User.create!(email: "no_actor@example.com")
      user.destroy!

      assert_nil Deletion.last.actor
    end
  end
end
