# frozen_string_literal: true

require "test_helper"

module Athar
  module Dashboard
    class ConnectionInfoTest < ActiveSupport::TestCase
      test "returns database name and pg version" do
        info = ConnectionInfo.fetch

        assert_kind_of String, info.database
        assert_match(/\Apg\d+\z/, info.version)
      end
    end
  end
end
