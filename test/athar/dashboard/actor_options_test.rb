# frozen_string_literal: true

require "test_helper"

module Athar
  module Dashboard
    class ActorOptionsTest < ActiveSupport::TestCase
      setup { @now = seed_audit_log! }

      test "returns users + system + anonymous groups" do
        result = ActorOptions.new(cutoff: @now - 30.days).call

        assert_kind_of Array, result.users
        assert_kind_of Array, result.system
        assert_equal "(anonymous)", result.anonymous_label
      end

      test "users group entries have value and label" do
        result = ActorOptions.new(cutoff: @now - 30.days).call
        result.users.each do |opt|
          assert_match(/\Auser:\w+:\w+\z/, opt[:value])
          assert_predicate opt[:label], :present?
        end
      end

      test "system group entries pull from metadata->>'actor'" do
        result = ActorOptions.new(cutoff: @now - 30.days).call
        names = result.system.map { |o| o[:value] }

        assert_includes names, "sys:retention_job"
        assert_includes names, "sys:cron"
      end

      test "respects cutoff" do
        result = ActorOptions.new(cutoff: @now - 1.hour).call
        # Far older actors should be excluded
        names = result.users.map { |o| o[:label] }

        assert_operator names.length, :<=, 5
      end
    end
  end
end
