# frozen_string_literal: true

Athar.configure do |config|
  config.retention.batch_size = 100
  config.retention.max_batches_per_run = 10
end
