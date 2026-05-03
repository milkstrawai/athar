# frozen_string_literal: true

require "active_support/isolated_execution_state"

module Athar
  # Fiber-aware metadata stack used by Athar::Context to merge nested
  # `with_metadata` blocks. Storage is delegated to ActiveSupport's
  # IsolatedExecutionState so the stack tracks the request/job execution
  # boundary correctly under fiber-based runtimes (Solid Queue, Falcon, etc.).
  class MetadataStack
    STATE_KEY = :athar_metadata_stack

    class << self
      def push(meta)
        stack << meta
        current
      end

      def pop
        stack.pop
        current
      end

      def current
        stack.reduce({}) { |acc, meta| acc.merge(meta) }
      end

      def clear!
        ActiveSupport::IsolatedExecutionState[STATE_KEY] = []
      end

      def stack
        ActiveSupport::IsolatedExecutionState[STATE_KEY] ||= []
      end
    end
  end
end
