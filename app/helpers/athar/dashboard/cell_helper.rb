# frozen_string_literal: true

module Athar
  module Dashboard
    # Visual atoms for the deletion-feed table cells: capture-mode/mask pills,
    # the kind glyph, copy buttons, the inline metadata preview, and the
    # actor-cell label/role helpers.
    module CellHelper
      def mode_pill(mode)
        content_tag(:span, mode, class: "pill mode-pill mode-#{mode}")
      end

      def mask_pill(masks)
        return nil if masks.blank?

        content_tag(:span, "m#{masks.length}", class: "pill mask-pill", title: "masks: #{masks.join(", ")}")
      end

      def kind_icon(kind)
        content_tag(:span, raw(kind == "truncate" ? icon_trunc : icon_del), class: "kind-icon kind-#{kind}")
      end

      def copy_button(value, label:)
        button_tag(type: "button",
                   class: "copy-btn",
                   aria: { label: "Copy #{label}" },
                   data: {
                     athar_copy: value,
                     athar_copy_label: label
                   }) do
          raw(icon_copy)
        end
      end

      def metadata_preview(metadata) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength
        # Drop "actor" since the actor column already renders it; the expanded
        # detail still shows the full unfiltered metadata.
        metadata = (metadata || {}).to_h.except("actor")

        return content_tag(:span, "{}", class: "muted") if metadata.empty?

        keys = metadata.keys
        pairs = keys.first(4).map do |key|
          value = metadata[key]
          value_text = value.is_a?(String) ? value : value.to_json

          content_tag(:span, class: "meta-kv") do
            safe_join(
              [
                content_tag(:span, ERB::Util.html_escape(key), class: "meta-k"),
                content_tag(:span, ERB::Util.html_escape(value_text), class: "meta-v")
              ],
              " "
            )
          end
        end

        separator = content_tag(:span, "·", class: "dot-sep")
        html = pairs.flat_map.with_index { |pair, index| index.zero? ? [pair] : [separator, pair] }
        html << content_tag(:span, "+#{keys.length - 4}", class: "dim") if keys.length > 4
        content_tag(:span, safe_join(html, " "), class: "summary-bits")
      end

      # Fallback used by _row.html.erb only when @actor_labels is missing an
      # entry, which happens for rows with NULL actor_id (system or anonymous).
      # Any row with a present actor_id has already been batch-resolved in the
      # controller.
      def actor_label(deletion)
        return "#{deletion[:actor_type]}##{deletion[:actor_id]}" if deletion[:actor_id].present?
        return deletion.dig(:metadata, "actor") if deletion[:metadata].is_a?(Hash) && deletion[:metadata]["actor"]

        "—"
      end

      # Returns one of: "engineer" (AR-backed actor), "job" (system actor via
      # metadata.actor), or "anonymous" (no actor info).
      def actor_role(row)
        if row[:actor_id].present?
          "engineer"
        elsif row[:metadata].is_a?(Hash) && row[:metadata]["actor"]
          "job"
        else
          "anonymous"
        end
      end
    end
  end
end
