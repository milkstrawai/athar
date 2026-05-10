# frozen_string_literal: true

require "test_helper"

module Athar
  module Dashboard
    class TriggerArgsParserTest < ActiveSupport::TestCase
      def parse(text) = TriggerArgsParser.parse(text)

      test "parses identity-only args" do
        args = parse("'User','public','users','id','bigint','null','identity','null','null'")

        assert_equal "User", args[0]
        assert_equal "public", args[1]
        assert_equal "users", args[2]
        assert_equal "id", args[3]
        assert_equal "bigint", args[4]
        assert_nil args[5]
        assert_equal "identity", args[6]
        assert_nil args[7]
        assert_nil args[8]
      end

      test "parses snapshot with masked email and partial phone" do
        args = parse("'User','public','users','id','bigint','null','snapshot'," +
                     %q('null','{"email:email","phone:partial:0:4"}'))

        assert_equal "snapshot", args[6]
        assert_nil args[7]
        assert_equal '{"email:email","phone:partial:0:4"}', args[8]
      end

      test "parses --only with array of columns" do
        args = parse("'User','public','users','id','bigint','null','only','{email,name,account_id}','null'")

        assert_equal "only", args[6]
        assert_equal "{email,name,account_id}", args[7]
      end

      test "parses sti record_type_column" do
        args = parse("'Admin','public','users','id','bigint','type','snapshot','null','null'")

        assert_equal "type", args[5]
      end

      test "handles whitespace and newlines between args" do
        args = parse(%('User',\n  'public',\n  'users',\n  'id',\n  'bigint',\n  'null',\n  'identity',\n  'null',\n  'null')) # rubocop:disable Layout/LineLength

        assert_equal "User", args[0]
      end

      test "handles escaped single quotes inside a quoted string (PG '' escape)" do
        args = parse("'it''s','public','users','id','bigint','null','identity','null','null'")

        assert_equal "it's", args[0]
      end
    end
  end
end
