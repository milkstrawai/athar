# frozen_string_literal: true

module Athar
  # Shared actor querying behavior for audit read models. Mixed into
  # Athar::Deletion and Athar::TableEvent.
  module ActorLookup
    extend ActiveSupport::Concern

    class_methods do
      def by_actor(actor_or_type, id = nil)
        if id.nil? && actor_or_type.is_a?(ActiveRecord::Base)
          where(actor_type: actor_or_type.class.base_class.name, actor_id: actor_or_type.id)
        else
          raise ArgumentError, "id is required when passing an actor class or type" if id.nil?

          klass_name = actor_or_type.is_a?(Class) ? actor_or_type.base_class.name : actor_or_type.to_s
          where(actor_type: klass_name, actor_id: id)
        end
      end

      def for_records(records)
        return records if records.empty?

        actor_map = build_actor_map(records)
        records.each { |r| r.instance_variable_set(:@actor, actor_map[[r.actor_type, r.actor_id]]) }
        records
      end

      def build_actor_map(records)
        actor_map = {}
        records.group_by { |r| [r.actor_type, r.actor_id] }.each_key do |type, id|
          next if type.blank? || id.nil?

          klass = type.safe_constantize
          next unless klass

          actor_map[[type, id]] = klass.find_by(klass.primary_key => id)
        end
        actor_map
      end
    end

    def actor
      return @actor if defined?(@actor)

      @actor = lookup_actor
    end

    def lookup_actor
      return nil if actor_type.blank? || actor_id.nil?

      klass = actor_type.safe_constantize
      return nil unless klass

      klass.find_by(klass.primary_key => actor_id)
    end
  end
end
