# frozen_string_literal: true

require_relative "actor_lookup"

module Athar
  class TableEvent < ActiveRecord::Base
    include ActorLookup

    EVENT_TYPE_TRUNCATE = "truncate"

    self.table_name = Athar::TABLE_EVENTS_TABLE_NAME

    class << self
      def recent
        order(occurred_at: :desc, id: :desc)
      end

      def for_table(table_name)
        where(table_name: table_name.to_s)
      end

      def truncate
        where(event_type: EVENT_TYPE_TRUNCATE)
      end
    end
  end
end
