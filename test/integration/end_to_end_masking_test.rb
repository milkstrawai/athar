# frozen_string_literal: true

require "test_helper"

module Athar
  class EndToEndMaskingTest < ActiveSupport::TestCase
    setup do
      regenerate_user_trigger_with_mask("email:email,name:partial:1:1")
    end

    teardown do
      regenerate_user_trigger_with_mask(nil)
    end

    test "destroy! captures masked record_data" do
      user = User.create!(email: "user.name@example.com", name: "Aliosm")
      user.destroy!

      data = Deletion.last.record_data

      assert_equal "use***@example.com", data["email"]
      assert_equal "A****m", data["name"]
    end

    test "delete_all captures masked record_data per row" do
      User.create!(email: "first@example.com", name: "First")
      User.create!(email: "second@example.com", name: "Secondx")

      User.delete_all

      emails = Deletion.all.pluck(:record_data).map { |d| d["email"] }.sort

      assert_equal ["fir***@example.com", "sec***@example.com"], emails
    end

    test "raw SQL DELETE captures masked record_data" do
      user = User.create!(email: "raw@example.com", name: "Rawx")
      ActiveRecord::Base.connection.execute(
        "DELETE FROM users WHERE id = #{user.id}"
      )

      assert_equal "raw***@example.com", Deletion.last.record_data["email"]
    end

    test "custom mask function is called via EXECUTE for non-built-in mask names" do
      # Install a custom mask function matching the documented
      # athar_mask_<name>(value jsonb) RETURNS jsonb contract.
      ActiveRecord::Base.connection.execute(<<~SQL)
        CREATE OR REPLACE FUNCTION athar_mask_keep_first(value jsonb) RETURNS jsonb AS $$
        DECLARE text_value text;
        BEGIN
          IF value IS NULL OR jsonb_typeof(value) <> 'string' THEN
            RETURN value;
          END IF;
          text_value := value #>> '{}';
          RETURN to_jsonb(regexp_replace(text_value, '(.).*', '\\1***'));
        END;
        $$ LANGUAGE plpgsql IMMUTABLE;
      SQL

      regenerate_user_trigger_with_mask("name:keep_first")

      user = User.create!(email: "x@y.io", name: "Aliosm")
      user.destroy!

      assert_equal "A***", Deletion.last.record_data["name"]
    ensure
      # Restore the no-mask trigger first (so the mask-using trigger doesn't
      # outlive the function we're about to drop).
      regenerate_user_trigger_with_mask(nil)
      ActiveRecord::Base.connection.execute("DROP FUNCTION IF EXISTS athar_mask_keep_first(jsonb)")
    end

    private

    def regenerate_user_trigger_with_mask(mask_spec)
      # Build a generator with the desired options and directly apply the
      # trigger SQL. This avoids writing new migration files (which would
      # collide on the AtharTriggerUsers class name) and is safe to call
      # from both setup and teardown.
      opts = {
        fx: false,
        only: %w[email name tags preferences status mood handle created_at]
      }
      opts[:mask] = Array(mask_spec) if mask_spec

      generator = Athar::Generators::ModelGenerator.new(["User"], opts)

      conn = ActiveRecord::Base.connection
      conn.execute(generator.send(:drop_trigger_sql))
      conn.execute(generator.send(:trigger_sql))
    end
  end
end
