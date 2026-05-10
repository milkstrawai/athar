# frozen_string_literal: true

module Athar
  module Dashboard
    # Immutable value object holding the parsed query-param state for a
    # dashboard request. Exposed by DashboardController#index as @filters and
    # consumed by FeedQuery, KpiCalculator, ActorOptions, and the partials.
    class FilterSet
      TIMES = { "24h" => 24.hours, "7d" => 7.days, "30d" => 30.days, "all" => nil }.freeze
      MODES = %w[all identity only snapshot].freeze
      KINDS = %w[all delete truncate].freeze
      DEFAULT_TIME = "30d"

      attr_reader :model, :time, :mode, :kind, :actor, :query, :page, :expanded

      def self.from_params(params) # rubocop:disable Metrics/AbcSize
        new(
          model: params[:model].presence,
          time: TIMES.key?(params[:time]) ? params[:time] : DEFAULT_TIME,
          mode: MODES.include?(params[:mode]) ? params[:mode] : "all",
          kind: KINDS.include?(params[:kind]) ? params[:kind] : "all",
          actor: params[:actor].presence || "all",
          query: params[:q].to_s,
          page: [params[:page].to_i, 1].max,
          expanded: params[:expanded].presence
        )
      end

      def initialize(model:, time:, mode:, kind:, actor:, query:, page:, expanded:) # rubocop:disable Metrics/ParameterLists
        @model = model
        @time = time
        @mode = mode
        @kind = kind
        @actor = actor
        @query = query
        @page = page
        @expanded = expanded

        freeze
      end

      def time_cutoff(now = Time.current)
        delta = TIMES[time]
        delta ? now - delta : nil
      end

      def actor_filter
        return nil if actor == "all"

        if actor == "anon"
          { kind: :anon }
        elsif actor.start_with?("user:")
          _, type, id = actor.split(":", 3)
          return nil if id.blank?

          { kind: :user, type:, id: }
        elsif actor.start_with?("sys:")
          { kind: :sys, name: actor.sub("sys:", "") }
        end
      end
    end
  end
end
