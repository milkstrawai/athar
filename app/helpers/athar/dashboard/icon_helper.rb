# frozen_string_literal: true

module Athar
  module Dashboard
    # Inline SVG icon library. Each method returns a raw SVG string; callers
    # are responsible for marking it html_safe (typically via `raw(...)`) when
    # the icon needs to embed in surrounding HTML.
    module IconHelper
      # rubocop:disable Layout/LineLength
      def icon_chev_right
        %(<svg viewBox="0 0 16 16" width="12" height="12" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M6 4l4 4-4 4"/></svg>)
      end

      def icon_chev_down
        %(<svg viewBox="0 0 16 16" width="12" height="12" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M4 6l4 4 4-4"/></svg>)
      end

      def icon_search
        %(<svg viewBox="0 0 16 16" width="12" height="12" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M7 12a5 5 0 1 0 0-10 5 5 0 0 0 0 10zM11 11l3 3"/></svg>)
      end

      def icon_copy
        %(<svg viewBox="0 0 16 16" width="11" height="11" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><rect x="5" y="5" width="9" height="9" rx="1.5"/><path d="M11 5V3a1 1 0 0 0-1-1H3a1 1 0 0 0-1 1v7a1 1 0 0 0 1 1h2"/></svg>)
      end

      def icon_check
        %(<svg viewBox="0 0 16 16" width="11" height="11" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M3 8l3 3 7-7"/></svg>)
      end

      def icon_trunc
        %(<svg viewBox="0 0 16 16" width="11" height="11" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M2 8h12M5 5l-3 3 3 3M11 11l3-3-3-3"/></svg>)
      end

      def icon_del
        %(<svg viewBox="0 0 16 16" width="11" height="11" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M3 4h10M5 4V3a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v1M4 4l1 9a1 1 0 0 0 1 1h4a1 1 0 0 0 1-1l1-9"/></svg>)
      end
      # rubocop:enable Layout/LineLength
    end
  end
end
