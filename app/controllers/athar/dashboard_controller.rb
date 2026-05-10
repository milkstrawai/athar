# frozen_string_literal: true

module Athar
  class DashboardController < ApplicationController
    PER_PAGE = 25

    def index # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
      @filters = Dashboard::FilterSet.from_params(params)
      @now     = Time.current

      @registry       = Dashboard::ModelRegistry.discover
      @registry_by_id = @registry.index_by { |model| [model.schema, model.table] }
      @selected_model = @registry.find { |model| model.record_type == @filters.model } if @filters.model

      feed_query = Dashboard::FeedQuery.new(filters: @filters, per_page: PER_PAGE, now: @now, registry: @registry)
      @rows  = feed_query.call
      @total = feed_query.total

      @page = {
        current: @filters.page,
        last: [(@total.to_f / PER_PAGE).ceil, 1].max,
        total: @total,
        per_page: PER_PAGE
      }

      @actor_labels    = resolve_actor_labels(@rows)
      @kpis            = Dashboard::KpiCalculator.new(model: @filters.model, now: @now, registry: @registry).call
      @actors          = Dashboard::ActorOptions.new(cutoff: @filters.time_cutoff(@now) || (@now - 30.days)).call
      @connection_info = Dashboard::ConnectionInfo.fetch
    end

    private

    def resolve_actor_labels(rows) # rubocop:disable Metrics/AbcSize
      actor_pairs = rows.filter_map do |row|
        [row[:actor_type], row[:actor_id]] if row[:actor_id].present?
      end.uniq

      actor_pairs.group_by(&:first).each_with_object({}) do |(actor_type, pairs_for_type), labels|
        actor_ids = pairs_for_type.map(&:last)
        records_by_id = batch_fetch_actor_records(actor_type, actor_ids)

        actor_ids.each do |actor_id|
          labels[[actor_type, actor_id]] =
            Dashboard::ActorLabels.humanize(records_by_id[actor_id], actor_type, actor_id)
        end
      end
    end

    def batch_fetch_actor_records(actor_type, actor_ids)
      klass = actor_type.safe_constantize
      return {} unless klass.respond_to?(:where)

      klass.where(klass.primary_key => actor_ids).index_by { |record| record.id.to_s }
    end
  end
end
