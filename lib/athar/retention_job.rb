# frozen_string_literal: true

module Athar
  class RetentionJob < ActiveJob::Base
    queue_as { Athar.configuration.retention.queue_name || :default }

    def perform(max_age: nil, max_count: nil, batch_size: nil, max_batches: nil)
      Athar::Retention.prune!(max_age:, max_count:, batch_size:, max_batches:)
    end
  end
end
