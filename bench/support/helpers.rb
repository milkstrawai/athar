# frozen_string_literal: true

require "active_record"

module Bench
  module Helpers
    class << self
      def env_integer(name, default, positive: false, non_negative: false)
        value = Integer(ENV.fetch(name, default))

        raise ArgumentError, "#{name} must be positive" if positive && !value.positive?
        raise ArgumentError, "#{name} cannot be negative" if non_negative && value.negative?

        value
      end

      def establish_connection!(database:)
        ActiveRecord::Base.establish_connection(
          adapter: "postgresql",
          host: ENV.fetch("ATHAR_DB_HOST", "localhost"),
          port: ENV.fetch("ATHAR_DB_PORT", 5434),
          username: ENV.fetch("ATHAR_DB_USER", "athar"),
          password: ENV.fetch("ATHAR_DB_PASSWORD", "athar"),
          database: ENV.fetch("ATHAR_DB_NAME", database)
        )

        ActiveRecord::Base.connection
      end

      def reset_athar_session!(connection)
        connection.execute("RESET athar.disabled")
        connection.execute("RESET athar.meta")
      end

      def stats(times, denominator)
        sorted = times.sort
        median = sorted[times.length / 2]

        {
          median: median,
          mean: times.sum / times.length,
          min: sorted.first,
          max: sorted.last,
          rate: denominator / median
        }
      end
    end
  end
end
