# frozen_string_literal: true

require "active_support/isolated_execution_state"

module Athar
  # Fiber-aware metadata stack used by Athar::Context to merge nested
  # `with_metadata` blocks. Storage is delegated to ActiveSupport's
  # IsolatedExecutionState so the stack tracks the request/job execution
  # boundary correctly under fiber-based runtimes (Solid Queue, Falcon, etc.).
  class MetadataStack
    STATE_KEY = :athar_metadata_stack
    CACHE_KEY = :athar_metadata_stack_cache

    class << self
      def push(meta)
        stack << meta
        self.current_cache = current_cache ? current_cache.merge(meta) : stack.reduce({}) { |acc, m| acc.merge(m) }
      end

      def pop
        stack.pop
        self.current_cache = nil
        current
      end

      def current
        current_cache || (self.current_cache = stack.reduce({}) { |acc, meta| acc.merge(meta) })
      end

      def clear!
        ActiveSupport::IsolatedExecutionState[STATE_KEY] = []
        self.current_cache = nil
      end

      def stack
        ActiveSupport::IsolatedExecutionState[STATE_KEY] ||= []
      end

      private

      def current_cache
        ActiveSupport::IsolatedExecutionState[CACHE_KEY]
      end

      def current_cache=(value)
        ActiveSupport::IsolatedExecutionState[CACHE_KEY] = value
      end
    end
  end
end
