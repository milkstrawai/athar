# frozen_string_literal: true

require "test_helper"

module Athar
  class DataMaskingTest < ActiveSupport::TestCase # rubocop:disable Metrics/ClassLength
    # ---- athar_mask_email ----

    test "athar_mask_email keeps first 3 chars of local part with 3 asterisks" do
      assert_equal "use***@example.com", mask_email("user.name@example.com")
    end

    test "athar_mask_email keeps short local part untouched, still adds 3 asterisks" do
      assert_equal "ab***@x.io", mask_email("ab@x.io")
    end

    test "athar_mask_email passes through non-email strings unchanged" do
      assert_equal "no-at-sign", mask_email("no-at-sign")
    end

    test "athar_mask_email passes NULL through" do
      assert_nil mask_jsonb("athar_mask_email(NULL::jsonb)")
    end

    test "athar_mask_email passes through non-string JSON values" do
      assert_equal 42, mask_jsonb("athar_mask_email('42'::jsonb)")
      assert mask_jsonb("athar_mask_email('true'::jsonb)")
    end

    # ---- athar_mask_partial ----

    test "athar_mask_partial keeps head and tail" do
      assert_equal "************1111", mask_partial("4111111111111111", 0, 4)
    end

    test "athar_mask_partial preserves head and tail symmetrically" do
      assert_equal "ab**ef", mask_partial("abcdef", 2, 2)
    end

    test "athar_mask_partial 0,0 returns all asterisks length-preserved" do
      assert_equal "*****", mask_partial("hello", 0, 0)
    end

    test "athar_mask_partial when head+tail equals length returns all asterisks" do
      assert_equal "****", mask_partial("abcd", 2, 2)
    end

    test "athar_mask_partial when head+tail exceeds length returns all asterisks" do
      assert_equal "***", mask_partial("abc", 5, 5)
    end

    test "athar_mask_partial passes through non-string JSON" do
      assert_equal 42, mask_jsonb("athar_mask_partial('42'::jsonb, 0, 1)")
    end

    test "athar_mask_partial NULL passes through" do
      assert_nil mask_jsonb("athar_mask_partial(NULL::jsonb, 0, 1)")
    end

    test "athar_mask_partial raises on negative arg" do
      assert_raises(ActiveRecord::StatementInvalid) do
        mask_partial("abcdef", -1, 2)
      end
    end

    # ---- athar_mask_hash ----

    test "athar_mask_hash returns SHA-256 hex of string" do
      expected = Digest::SHA256.hexdigest("user.name@example.com")

      assert_equal expected, mask_hash("user.name@example.com")
    end

    test "athar_mask_hash is deterministic" do
      assert_equal mask_hash("same"), mask_hash("same")
    end

    test "athar_mask_hash differs across distinct inputs" do
      refute_equal mask_hash("a"), mask_hash("b")
    end

    test "athar_mask_hash hashes the textual form of non-string scalars" do
      expected = Digest::SHA256.hexdigest("42")

      assert_equal expected, mask_jsonb("athar_mask_hash('42'::jsonb)")
    end

    test "athar_mask_hash NULL passes through" do
      assert_nil mask_jsonb("athar_mask_hash(NULL::jsonb)")
    end

    # ---- athar_apply_masks dispatcher ----

    test "athar_apply_masks dispatches email" do
      result = apply_masks(
        { "email" => "user.name@example.com", "name" => "Ali" },
        ["email:email"]
      )

      assert_equal({ "email" => "use***@example.com", "name" => "Ali" }, result)
    end

    test "athar_apply_masks dispatches partial with args" do
      result = apply_masks({ "phone" => "12345678" }, ["phone:partial:0:4"])

      assert_equal({ "phone" => "****5678" }, result)
    end

    test "athar_apply_masks dispatches hash" do
      expected = Digest::SHA256.hexdigest("ali@x")
      result = apply_masks({ "email" => "ali@x" }, ["email:hash"])

      assert_equal({ "email" => expected }, result)
    end

    test "athar_apply_masks applies multiple specs sequentially" do
      result = apply_masks(
        { "email" => "user.name@example.com", "phone" => "12345678" },
        ["email:email", "phone:partial:0:4"]
      )

      assert_equal(
        { "email" => "use***@example.com", "phone" => "****5678" },
        result
      )
    end

    test "athar_apply_masks silently skips columns missing from data" do
      result = apply_masks({ "email" => "a@b.io" }, ["ghost:email"])

      assert_equal({ "email" => "a@b.io" }, result)
    end

    test "athar_apply_masks empty mask array returns data unchanged" do
      data = { "email" => "a@b.io" }

      assert_equal data, apply_masks(data, [])
    end

    test "athar_apply_masks NULL data returns NULL" do
      assert_nil mask_jsonb("athar_apply_masks(NULL::jsonb, ARRAY['email:email']::text[])")
    end

    test "athar_apply_masks NULL masks returns data unchanged" do
      result = mask_jsonb(
        %(athar_apply_masks('{"email":"a@b"}'::jsonb, NULL::text[]))
      )

      assert_equal({ "email" => "a@b" }, result)
    end

    test "athar_apply_masks preserves column when mask returns SQL NULL (COALESCE guard)" do
      # If a mask returns SQL NULL, jsonb_set would propagate NULL through its
      # new_value argument and wipe the entire data jsonb. The dispatcher must
      # COALESCE to JSON null. We exercise this by installing a fixture mask
      # that always returns SQL NULL — without the COALESCE, this test would
      # produce { } (data wiped) instead of { "email" => nil, "name" => "Ali" }.
      ActiveRecord::Base.connection.execute(<<~SQL)
        CREATE OR REPLACE FUNCTION athar_mask_test_returns_null(value jsonb) RETURNS jsonb AS $$
        BEGIN
          RETURN NULL;
        END;
        $$ LANGUAGE plpgsql;
      SQL

      result = apply_masks(
        { "email" => "real@example.com", "name" => "Ali" },
        ["email:test_returns_null"]
      )

      assert_equal({ "email" => nil, "name" => "Ali" }, result)
    ensure
      ActiveRecord::Base.connection.execute("DROP FUNCTION IF EXISTS athar_mask_test_returns_null(jsonb)")
    end

    test "athar_apply_masks dispatches custom function via EXECUTE" do
      ActiveRecord::Base.connection.execute(<<~SQL)
        CREATE OR REPLACE FUNCTION athar_mask_test_uppercase(value jsonb) RETURNS jsonb AS $$
        BEGIN
          IF value IS NULL OR jsonb_typeof(value) <> 'string' THEN RETURN value; END IF;
          RETURN to_jsonb(upper(value #>> '{}'));
        END;
        $$ LANGUAGE plpgsql IMMUTABLE;
      SQL

      result = apply_masks({ "code" => "abc" }, ["code:test_uppercase"])

      assert_equal({ "code" => "ABC" }, result)
    ensure
      ActiveRecord::Base.connection.execute("DROP FUNCTION IF EXISTS athar_mask_test_uppercase(jsonb)")
    end

    # ---- athar_capture_delete TG_ARGV[8] integration ----

    test "athar_capture_delete masks columns when TG_ARGV[8] supplies a spec" do
      ActiveRecord::Base.connection.execute(<<~SQL)
        DROP TRIGGER IF EXISTS athar_on_users_test_mask ON public.users;
        CREATE TRIGGER athar_on_users_test_mask
        BEFORE DELETE ON public.users
        FOR EACH ROW
        WHEN (coalesce(current_setting('athar.disabled', true), '') <> 'on')
        EXECUTE PROCEDURE athar_capture_delete(
          'User',
          'public',
          'users',
          'id',
          'bigint',
          '__athar_none__',
          'snapshot',
          '__athar_none__',
          '{"email:email"}'
        );
      SQL
      ActiveRecord::Base.connection.execute("DROP TRIGGER IF EXISTS athar_on_users ON public.users")

      user = User.create!(email: "user.name@example.com", name: "Ali")
      user.destroy!

      deletion = Athar::Deletion.last

      assert_equal "use***@example.com", deletion.record_data["email"]
      assert_equal "Ali", deletion.record_data["name"]
    ensure
      ActiveRecord::Base.connection.execute("DROP TRIGGER IF EXISTS athar_on_users_test_mask ON public.users")
    end

    test "athar_capture_delete with TG_ARGV[8] = '__athar_none__' is a no-op (backward compat)" do
      ActiveRecord::Base.connection.execute(<<~SQL)
        DROP TRIGGER IF EXISTS athar_on_users_test_no_mask ON public.users;
        CREATE TRIGGER athar_on_users_test_no_mask
        BEFORE DELETE ON public.users
        FOR EACH ROW
        WHEN (coalesce(current_setting('athar.disabled', true), '') <> 'on')
        EXECUTE PROCEDURE athar_capture_delete(
          'User','public','users','id','bigint','__athar_none__','snapshot','__athar_none__','__athar_none__'
        );
      SQL
      ActiveRecord::Base.connection.execute("DROP TRIGGER IF EXISTS athar_on_users ON public.users")

      user = User.create!(email: "user.name@example.com", name: "Ali")
      user.destroy!

      assert_equal "user.name@example.com", Athar::Deletion.last.record_data["email"]
    ensure
      ActiveRecord::Base.connection.execute("DROP TRIGGER IF EXISTS athar_on_users_test_no_mask ON public.users")
    end

    test "athar_capture_delete works with the legacy 8-arg call shape (backward compat)" do
      ActiveRecord::Base.connection.execute(<<~SQL)
        DROP TRIGGER IF EXISTS athar_on_users_test_legacy ON public.users;
        CREATE TRIGGER athar_on_users_test_legacy
        BEFORE DELETE ON public.users
        FOR EACH ROW
        WHEN (coalesce(current_setting('athar.disabled', true), '') <> 'on')
        EXECUTE PROCEDURE athar_capture_delete(
          'User','public','users','id','bigint','__athar_none__','snapshot','__athar_none__'
        );
      SQL
      ActiveRecord::Base.connection.execute("DROP TRIGGER IF EXISTS athar_on_users ON public.users")

      user = User.create!(email: "user.name@example.com", name: "Ali")
      user.destroy!

      assert_equal "user.name@example.com", Athar::Deletion.last.record_data["email"]
    ensure
      ActiveRecord::Base.connection.execute("DROP TRIGGER IF EXISTS athar_on_users_test_legacy ON public.users")
    end

    private

    def mask_email(value)
      mask_jsonb("athar_mask_email(to_jsonb(?::text))", value)
    end

    def mask_partial(value, head, tail)
      mask_jsonb("athar_mask_partial(to_jsonb(?::text), ?::int, ?::int)", value, head, tail)
    end

    def mask_hash(value)
      mask_jsonb("athar_mask_hash(to_jsonb(?::text))", value)
    end

    def mask_jsonb(expr, *binds)
      raw = ActiveRecord::Base.connection.select_value(
        ActiveRecord::Base.sanitize_sql_array(["SELECT (#{expr})::text", *binds])
      )
      raw.nil? ? nil : JSON.parse(raw)
    end

    def apply_masks(data_hash, masks_array)
      pg_masks = "{#{masks_array.map { |m| %("#{m}") }.join(",")}}"
      raw = ActiveRecord::Base.connection.select_value(
        ActiveRecord::Base.sanitize_sql_array([
                                                "SELECT athar_apply_masks(?::jsonb, ?::text[])::text",
                                                data_hash.to_json, pg_masks
                                              ])
      )
      JSON.parse(raw)
    end
  end
end
