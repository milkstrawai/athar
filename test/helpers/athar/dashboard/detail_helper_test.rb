# frozen_string_literal: true

require "test_helper"

module Athar
  module Dashboard
    class DetailHelperTest < ActionView::TestCase
      include Athar::DashboardHelper

      # ---- render_json_kv empty paths ----

      test "render_json_kv nil renders empty placeholder" do
        assert_includes render_json_kv(nil), "{}"
        assert_match(/json-empty/, render_json_kv(nil))
      end

      test "render_json_kv empty hash renders empty placeholder" do
        assert_includes render_json_kv({}), "{}"
        assert_match(/json-empty/, render_json_kv({}))
      end

      test "render_json_kv populated hash renders kv table" do
        html = render_json_kv("email" => "a@b.com", "count" => 3)

        assert_match(/kv-table/, html)
        assert_match(/kv-key.*email/, html)
        assert_match(/kv-key.*count/, html)
      end

      # ---- format_kv_value branches ----

      test "format_kv_value masks strings containing ***" do
        html = format_kv_value("use***@nimbus.app")

        assert_match(/class="masked"/, html)
        assert_includes html, "use***@nimbus.app"
      end

      test "format_kv_value plain string is escaped, not wrapped" do
        html = format_kv_value("hello <world>")

        assert_includes html, "hello &lt;world&gt;"
        refute_match(/class="masked"/, html)
        refute_match(/class="num"/, html)
      end

      test "format_kv_value nil renders muted null" do
        html = format_kv_value(nil)

        assert_match(/class="muted"/, html)
        assert_includes html, "null"
      end

      test "format_kv_value true and false render as bool" do
        assert_match(/class="bool".*true/,  format_kv_value(true))
        assert_match(/class="bool".*false/, format_kv_value(false))
      end

      test "format_kv_value integer renders as num" do
        assert_match(/class="num".*42/, format_kv_value(42))
      end

      test "format_kv_value float renders as num" do
        assert_match(/class="num".*3\.14/, format_kv_value(3.14))
      end

      test "format_kv_value escapes HTML in masked strings" do
        html = format_kv_value("***<script>")

        assert_includes html, "&lt;script&gt;"
      end
    end
  end
end
