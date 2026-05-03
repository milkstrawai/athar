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
    end

    def actor
      return nil if actor_type.blank? || actor_id.nil?

      klass = actor_type.safe_constantize
      return nil unless klass

      klass.find_by(klass.primary_key => actor_id)
    end
  end
end
