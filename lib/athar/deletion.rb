# frozen_string_literal: true

require_relative "actor_lookup"

module Athar
  class Deletion < ActiveRecord::Base
    include ActorLookup

    self.table_name = Athar::DELETIONS_TABLE_NAME

    class << self
      def recent
        order(deleted_at: :desc, id: :desc)
      end

      def for_record(record_or_class, id = nil)
        # Filter by (schema_name, table_name, record_id):
        #   - `record_type` is unreliable because STI subclass rows are stored
        #     under the concrete class name (`"Admin"`) while
        #     `Admin.base_class.name` is `"User"`.
        #   - Active Record returns `"reporting.reporting_buckets"` for models
        #     in non-public schemas, but Athar stores schema and table in
        #     separate columns. Splitting on `.` mirrors what the generator
        #     does at trigger-install time.
        if id.nil? && record_or_class.is_a?(ActiveRecord::Base)
          schema, table = split_schema_qualified(record_or_class.class.table_name)
          where(schema_name: schema, table_name: table, record_id: record_or_class.id)
        else
          raise ArgumentError, "id is required when passing a record class or type" if id.nil?

          klass = record_or_class.is_a?(Class) ? record_or_class : constantize_cached(record_or_class.to_s)
          schema, table = split_schema_qualified(klass.table_name)
          where(schema_name: schema, table_name: table, record_id: id)
        end
      end

      def for_record_type(type)
        where(record_type: type.to_s)
      end

      def for_table(table_name)
        where(table_name: table_name.to_s)
      end

      def before(time)
        where(arel_table[:deleted_at].lt(time))
      end

      def after(time)
        where(arel_table[:deleted_at].gt(time))
      end

      private

      def constantize_cached(str)
        @constantize_cache ||= {}
        @constantize_cache[str] ||= str.constantize
      end

      def split_schema_qualified(qualified)
        full = qualified.to_s
        full.include?(".") ? full.split(".", 2) : [Athar.configuration.default_schema, full]
      end
    end
  end
end
