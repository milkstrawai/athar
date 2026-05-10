# frozen_string_literal: true

module Athar
  module Dashboard
    # URL builders for filter-bar / sidebar / pager navigation. Strips
    # `page` and `expanded` on every filter change and drops any param whose
    # value matches its real default, so URLs stay clean (no "?mode=all")
    # while preserving non-default values like "time=all" (default for `time`
    # is "30d", not "all").
    module FilterLinkHelper
      FILTER_DEFAULTS = { "time" => "30d", "mode" => "all", "kind" => "all", "actor" => "all" }.freeze

      def filter_link_url(replacements = {})
        preserved = request.query_parameters.except("page", "expanded", *replacements.keys.map(&:to_s))
        preserved.merge!(replacements.transform_keys(&:to_s))
        preserved.delete_if { |key, value| value.blank? || FILTER_DEFAULTS[key.to_s] == value }
        query = preserved.empty? ? "" : "?#{preserved.to_query}"
        "#{root_path}#{query}"
      end
    end
  end
end
