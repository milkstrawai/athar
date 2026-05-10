# frozen_string_literal: true

module Athar
  module Dashboard
    # Rendering helpers for the expanded-row detail: JSON-style key-value
    # tables for record_data and metadata, and the row-hash → AR-record
    # upgrade used when a row is opened inline.
    module DetailHelper
      def render_json_kv(hash)
        if hash.blank? || (hash.is_a?(Hash) && hash.empty?)
          return content_tag(:div, "{}".html_safe, class: "json-empty")
        end

        rows = hash.map do |key, value|
          content_tag(:tr) do
            content_tag(:td, ERB::Util.html_escape(key), class: "kv-key") +
              content_tag(:td, format_kv_value(value), class: "kv-val")
          end
        end

        content_tag(:table, content_tag(:tbody, safe_join(rows)), class: "kv-table")
      end

      def format_kv_value(value) # rubocop:disable Metrics/MethodLength
        if value.is_a?(String) && value.include?("***")
          content_tag(:span, ERB::Util.html_escape(value), class: "masked")
        elsif value.nil?
          content_tag(:span, "null", class: "muted")
        elsif [true, false].include?(value)
          content_tag(:span, value.to_s, class: "bool")
        elsif value.is_a?(Numeric)
          content_tag(:span, value.to_s, class: "num")
        else
          ERB::Util.html_escape(value.to_s)
        end
      end

      # Upgrade a feed-row hash to its AR record so the detail partials can
      # call `.actor` (via ActorLookup), associations, etc. At most one row is
      # expanded at a time, so the cost is one extra query per render.
      def deletion_for(row)
        Athar::Deletion.find(row[:id])
      end

      def table_event_for(row)
        Athar::TableEvent.find(row[:id])
      end
    end
  end
end
