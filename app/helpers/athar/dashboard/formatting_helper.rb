# frozen_string_literal: true

module Athar
  module Dashboard
    # Compact, terminal-style formatters for time, duration, and large
    # numbers — used in the table rows, sidebar, KPI strip, and topbar.
    module FormattingHelper
      def relative_time(time, now: Time.current)
        diff = (now - time).to_i
        return "#{diff}s ago" if diff < 60
        return "#{diff / 60}m ago" if diff < 3_600
        return "#{diff / 3_600}h ago" if diff < 86_400
        return "#{diff / 86_400}d ago" if diff < 604_800

        "#{diff / 604_800}w ago"
      end

      def absolute_time(time)
        time.utc.strftime("%Y-%m-%d %H:%M:%SZ")
      end

      # Format a large integer compactly: 1_200_000 → "1.2M", 150_000 → "150K".
      def compact_number(number)
        return number.to_s if number.nil? || number < 1_000

        if number >= 1_000_000
          formatted = (number / 1_000_000.0).round(1)
          "#{formatted.to_s.sub(/\.0$/, "")}M"
        else
          formatted = (number / 1_000.0).round(1)
          "#{formatted.to_s.sub(/\.0$/, "")}K"
        end
      end

      # Format a duration in seconds as "Xd", "Xy", etc. Used by the sidebar's
      # retention pill.
      def compact_duration(seconds)
        return "—" if seconds.nil?

        days = seconds / 86_400
        return "#{days / 365}y" if days >= 730

        "#{days}d"
      end
    end
  end
end
