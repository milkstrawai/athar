# frozen_string_literal: true

module Athar
  module Context
    PG_META_KEY = "athar.meta"
    PG_DISABLED_KEY = "athar.disabled"

    class << self
      def with_actor(actor, &block)
        raise ArgumentError, "block required" unless block

        return block.call if actor.nil?

        unless actor.is_a?(ActiveRecord::Base)
          raise ArgumentError,
                "Athar.with_actor only accepts ActiveRecord instances. " \
                "Use Athar.with_metadata(actor: #{actor.inspect}) for symbolic actors."
        end

        meta = {
          "actor_type" => actor.class.base_class.name,
          "actor_id" => actor.public_send(actor.class.primary_key)
        }

        with_metadata(meta, &block)
      end

      def with_metadata(meta = nil, **kwargs, &block) # rubocop:disable Metrics/MethodLength
        raise ArgumentError, "block required" unless block

        normalized = normalize_meta(meta, kwargs)
        return block.call if normalized.empty?

        run_in_transaction do
          previous_merged = MetadataStack.current
          MetadataStack.push(normalized)
          begin
            apply_meta(MetadataStack.current)
            block.call
          ensure
            MetadataStack.pop
            apply_meta(previous_merged) if connection.transaction_open?
          end
        end
      end

      def with_context(actor: nil, **metadata, &block)
        raise ArgumentError, "block required" unless block

        return with_actor(actor, &block) if metadata.empty?
        return with_metadata(metadata, &block) if actor.nil?

        with_actor(actor) { with_metadata(metadata, &block) }
      end

      def without_capture(&block)
        raise ArgumentError, "block required" unless block

        run_in_transaction do
          previous = read_disabled_setting
          set_local(PG_DISABLED_KEY, "on")
          begin
            block.call
          ensure
            restore_disabled_setting(previous) if connection.transaction_open?
          end
        end
      end

      private

      def normalize_meta(meta, kwargs)
        result = {}
        result.merge!(meta.transform_keys(&:to_s)) if meta.is_a?(Hash) && !meta.empty?
        result.merge!(kwargs.transform_keys(&:to_s)) unless kwargs.empty?
        result
      end

      def apply_meta(merged)
        if merged.empty?
          reset_local(PG_META_KEY)
        else
          encoded = ActiveSupport::JSON.encode(merged)
          set_local(PG_META_KEY, encoded)
        end
      end

      def read_disabled_setting
        connection.select_value("SELECT current_setting('#{PG_DISABLED_KEY}', true)").to_s
      end

      def restore_disabled_setting(previous)
        if previous.empty?
          reset_local(PG_DISABLED_KEY)
        else
          set_local(PG_DISABLED_KEY, previous)
        end
      end

      def run_in_transaction(&block)
        if connection.transaction_open?
          block.call
        else
          connection.transaction(requires_new: false, &block)
        end
      end

      def reset_local(key)
        connection.execute("SET LOCAL #{key} TO DEFAULT")
      end

      def set_local(key, value)
        connection.execute("SET LOCAL #{key} = #{connection.quote(value)}")
      end

      def connection
        ActiveRecord::Base.connection
      end
    end
  end
end
