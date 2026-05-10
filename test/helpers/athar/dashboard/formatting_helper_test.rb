# frozen_string_literal: true

require "test_helper"

module Athar
  module Dashboard
    class FormattingHelperTest < ActionView::TestCase
      include Athar::DashboardHelper

      # ---- relative_time ----

      test "seconds bucket" do
        now = Time.utc(2026, 5, 6, 14, 22, 0)

        assert_equal "37s ago", relative_time(now - 37, now: now)
        assert_equal "59s ago", relative_time(now - 59, now: now)
      end

      test "minutes bucket boundary" do
        now = Time.utc(2026, 5, 6, 14, 22, 0)

        assert_equal "1m ago",  relative_time(now - 60, now: now)
        assert_equal "37m ago", relative_time(now - 37.minutes, now: now)
        assert_equal "59m ago", relative_time(now - 59.minutes, now: now)
      end

      test "hours bucket boundary" do
        now = Time.utc(2026, 5, 6, 14, 22, 0)

        assert_equal "1h ago",  relative_time(now - 1.hour, now: now)
        assert_equal "23h ago", relative_time(now - 23.hours, now: now)
      end

      test "days bucket boundary" do
        now = Time.utc(2026, 5, 6, 14, 22, 0)

        assert_equal "1d ago", relative_time(now - 1.day, now: now)
        assert_equal "6d ago", relative_time(now - 6.days, now: now)
      end

      test "weeks bucket past 7 days" do
        now = Time.utc(2026, 5, 6, 14, 22, 0)

        assert_equal "1w ago", relative_time(now - 7.days, now: now)
        assert_equal "4w ago", relative_time(now - 30.days, now: now)
      end

      # ---- absolute_time ----

      test "absolute_time formats yyyy-mm-dd HH:MM:SSZ in UTC" do
        assert_equal "2026-05-06 14:22:00Z", absolute_time(Time.utc(2026, 5, 6, 14, 22, 0))
      end

      test "absolute_time converts non-UTC times to UTC" do
        local = Time.new(2026, 5, 6, 17, 22, 0, "+03:00")

        assert_equal "2026-05-06 14:22:00Z", absolute_time(local)
      end

      # ---- compact_number ----

      test "compact_number returns plain string under 1_000" do
        assert_equal "0",   compact_number(0)
        assert_equal "1",   compact_number(1)
        assert_equal "999", compact_number(999)
      end

      test "compact_number nil returns empty-ish string" do
        assert_equal "", compact_number(nil)
      end

      test "compact_number formats thousands with K" do
        assert_equal "1K",     compact_number(1_000)
        assert_equal "1.5K",   compact_number(1_500)
        assert_equal "9.5K",   compact_number(9_500)
        assert_equal "999.5K", compact_number(999_499)
        assert_equal "1000K",  compact_number(999_999) # boundary rounds up but stays in K branch
      end

      test "compact_number formats millions with M" do
        assert_equal "1M",   compact_number(1_000_000)
        assert_equal "1.2M", compact_number(1_200_000)
      end

      test "compact_number strips redundant .0 suffix" do
        # 1_000 → 1.0 → "1" (not "1.0K")
        refute_match(/\.0/, compact_number(1_000))
        refute_match(/\.0/, compact_number(1_000_000))
      end

      # ---- compact_duration ----

      test "compact_duration nil returns em dash" do
        assert_equal "—", compact_duration(nil)
      end

      test "compact_duration formats days under 730" do
        assert_equal "1d",   compact_duration(1.day.to_i)
        assert_equal "365d", compact_duration(365.days.to_i)
        assert_equal "729d", compact_duration(729.days.to_i)
      end

      test "compact_duration switches to years at 730 days" do
        assert_equal "2y",  compact_duration(730.days.to_i)
        assert_equal "5y",  compact_duration((5 * 365).days.to_i)
      end
    end
  end
end
