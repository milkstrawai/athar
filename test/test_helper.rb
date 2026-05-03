# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"

require_relative "dummy/config/environment"
require "rails/test_help"
require "minitest/autorun"
require "mocha/minitest"

require_relative "support/database_helpers"
require_relative "support/sql_helpers"

Athar::TestSupport::DatabaseHelpers.setup!

module ActiveSupport
  class TestCase
    include Athar::TestSupport::DatabaseHelpers
    include Athar::TestSupport::SqlHelpers

    self.use_transactional_tests = true

    setup do
      Athar.reset_configuration!
    end

    teardown do
      Athar.reset_configuration!
    end
  end
end
