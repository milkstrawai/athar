# frozen_string_literal: true

module Athar
  module Dashboard
    # Builds a human-readable label for an actor record. Real host apps may or
    # may not override `to_s` on their actor models (Devise's User typically
    # doesn't), so this falls back to common identifying attributes before
    # using `to_s`, and to "Type#id" when nothing readable is available.
    module ActorLabels
      IDENTIFYING_ATTRIBUTES = %i[email name username login handle].freeze

      class << self
        def humanize(record, type, id)
          return "#{type}##{id}" unless record

          IDENTIFYING_ATTRIBUTES.each do |attribute|
            next unless record.respond_to?(attribute)

            value = record.public_send(attribute)
            return value.to_s if value.present?
          end

          string = record.to_s
          return string if string.is_a?(String) && !string.start_with?("#<")

          "#{type}##{id}"
        end
      end
    end
  end
end
