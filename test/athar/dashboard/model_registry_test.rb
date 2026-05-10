# frozen_string_literal: true

require "test_helper"

module Athar
  module Dashboard
    class ModelRegistryTest < ActiveSupport::TestCase
      setup { seed_audit_log! }

      test "discovers tracked models from existing dummy triggers" do
        registry = ModelRegistry.discover

        # The dummy app has athar:model triggers installed for several models;
        # verify the expected User entry on public.users is recovered.
        user = registry.find { |m| m.schema == "public" && m.table == "users" && m.record_type == "User" }

        refute_nil user, "expected User on public.users in registry"
        assert_includes %w[identity only snapshot], user.capture_mode
      end

      test "returns ModelInfo with required attributes" do
        m = ModelRegistry.discover.first

        refute_nil m.schema
        refute_nil m.table
        refute_nil m.record_type
        refute_nil m.capture_mode
        assert_kind_of Array, m.columns || []
        assert_kind_of Array, m.masks || []
        assert_includes [true, false], m.sti
        assert_includes [true, false], m.truncate
        assert_kind_of Integer, m.count
      end

      test "STI children appear when audit rows exist for them" do
        # The dummy app has Admin (STI on users); the seed pushes Admin rows.
        registry = ModelRegistry.discover
        admin = registry.find { |m| m.record_type == "Admin" }

        refute_nil admin, "expected Admin STI child to appear (seed inserts Admin row)"
        assert_equal "users", admin.table
      end

      test "counts reflect athar_deletions exactly" do
        registry = ModelRegistry.discover
        user = registry.find { |m| m.record_type == "User" }
        # Seed inserts 5 User-typed rows on public.users (5min, 1h, 2d, 10d, 20d ago).
        assert_equal 5, user.count
      end
    end
  end
end
