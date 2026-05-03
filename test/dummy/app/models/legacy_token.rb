# frozen_string_literal: true

# `type` column exists but Athar is told to ignore STI via
# --record-type-column=false in the test bootstrap.
class LegacyToken < ApplicationRecord
  self.inheritance_column = nil
end
