# frozen_string_literal: true

require "strscan"

module Athar
  module Dashboard
    # Parses the comma-separated argument list captured from a trigger's
    # `EXECUTE PROCEDURE athar_capture_delete(...)` clause. Every arg is a
    # single-quoted string per the trigger templates, so the parser walks
    # quoted tokens (honoring PG's `''` escape for embedded apostrophes) and
    # maps the literal "null" token to Ruby nil.
    module TriggerArgsParser
      QUOTED_TOKEN = /'((?:[^']|'')*)'/
      SEPARATOR    = /[\s,]+/

      class << self
        def parse(input)
          scanner = StringScanner.new(input)
          args = []

          until scanner.eos?
            scanner.skip(SEPARATOR)
            break if scanner.eos?
            break unless scanner.scan(QUOTED_TOKEN)

            args << finalize(scanner[1].gsub("''", "'"))
          end

          args
        end

        private

        def finalize(token)
          return nil if token == "null"

          token
        end
      end
    end
  end
end
