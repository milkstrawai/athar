# frozen_string_literal: true

require "test_helper"

module Athar
  module Dashboard
    class FilterSetTest < ActiveSupport::TestCase
      def parse(params) = FilterSet.from_params(ActionController::Parameters.new(params))

      test "applies defaults when params empty" do
        f = parse({})

        assert_equal "30d", f.time
        assert_equal "all", f.mode
        assert_equal "all", f.kind
        assert_equal "all", f.actor
        assert_equal "", f.query
        assert_equal 1, f.page
        assert_nil f.expanded
        assert_nil f.model
      end

      test "parses time / mode / kind / page" do
        f = parse(time: "7d", mode: "snapshot", kind: "truncate", page: "3")

        assert_equal "7d", f.time
        assert_equal "snapshot", f.mode
        assert_equal "truncate", f.kind
        assert_equal 3, f.page
      end

      test "rejects invalid enum values, falls back to default" do
        f = parse(time: "lol", mode: "evil", kind: "rm")

        assert_equal "30d", f.time
        assert_equal "all", f.mode
        assert_equal "all", f.kind
      end

      test "page floor at 1" do
        assert_equal 1, parse(page: "0").page
        assert_equal 1, parse(page: "-7").page
        assert_equal 1, parse(page: "abc").page
      end

      test "computes time_cutoff" do
        now = Time.utc(2026, 5, 6, 14, 22, 0)

        assert_equal now - 24.hours,    parse(time: "24h").time_cutoff(now)
        assert_equal now - 7.days,      parse(time: "7d").time_cutoff(now)
        assert_equal now - 30.days,     parse(time: "30d").time_cutoff(now)
        assert_nil                      parse(time: "all").time_cutoff(now)
      end

      test "actor parsing" do
        assert_equal({ kind: :user, type: "User", id: "4" }, parse(actor: "user:User:4").actor_filter)
        assert_equal({ kind: :sys, name: "retention_job" }, parse(actor: "sys:retention_job").actor_filter)
        assert_equal({ kind: :anon }, parse(actor: "anon").actor_filter)
        assert_nil parse(actor: "all").actor_filter
        assert_nil parse(actor: "garbage").actor_filter
      end

      test "actor parsing ignores user: prefix without id segment" do
        assert_nil parse(actor: "user:User").actor_filter
      end
    end
  end
end
