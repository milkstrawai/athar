# frozen_string_literal: true

require "test_helper"

module Athar
  module Dashboard
    class KpiCalculatorTest < ActiveSupport::TestCase
      setup { @now = seed_audit_log! }

      # Seed reference (from test/support/audit_seeds.rb):
      #   13 deletion rows at ages: 5min, 1h, 2h, 3h, 6h, 8h, 9h, 10h, 2d, 5d, 10d, 20d, 45d
      #   2 table events at ages: 1d, 6d
      #   record_type = "User" rows: 5 (at 5min, 1h, 2d, 10d, 20d)

      test "scope_total covers deletions plus all table events" do
        kpi = KpiCalculator.new(model: nil, now: @now).call

        assert_equal 13 + 2, kpi.scope_total
      end

      test "computes time-window counts exactly" do
        kpi = KpiCalculator.new(model: nil, now: @now).call

        assert_equal 8,  kpi.last_24h            # rows at 5min..10h
        assert_equal 10, kpi.last_7d             # rows at 5min..5d
        assert_equal 1,  kpi.prior_7d            # row at 10d only
        assert_equal 3,  kpi.distinct_actors_30d # User#1, User#4, User#27
      end

      test "scoped by model only counts that record_type" do
        all  = KpiCalculator.new(model: nil, now: @now).call
        user = KpiCalculator.new(model: "User", now: @now).call

        assert_equal 5, user.scope_total
        assert_operator user.scope_total, :<, all.scope_total
      end

      test "truncate count covers last 30d table_events" do
        kpi = KpiCalculator.new(model: nil, now: @now).call

        assert_equal 2, kpi.truncates_30d
      end

      test "sparkline has 14 buckets summing to last-14d row count" do
        kpi = KpiCalculator.new(model: nil, now: @now).call

        assert_equal 14, kpi.sparkline.length
        assert(kpi.sparkline.all? { |bucket| bucket >= 0 })
        # 11 rows within last 14 days (row at 20d and 45d excluded).
        assert_equal 11, kpi.sparkline.sum
      end
    end
  end
end
