# frozen_string_literal: true

require "test_helper"

module Athar
  module Dashboard
    class CellHelperTest < ActionView::TestCase
      include Athar::DashboardHelper

      # ---- actor_label ----

      test "actor_label uses Type#id when actor_id is present" do
        row = { actor_type: "User", actor_id: 42, metadata: {} }

        assert_equal "User#42", actor_label(row)
      end

      test "actor_label falls back to metadata.actor when actor_id is nil" do
        row = { actor_type: nil, actor_id: nil, metadata: { "actor" => "retention_job" } }

        assert_equal "retention_job", actor_label(row)
      end

      test "actor_label returns em dash when no actor info" do
        row = { actor_type: nil, actor_id: nil, metadata: {} }

        assert_equal "—", actor_label(row)
      end

      # ---- actor_role ----

      test "actor_role engineer when actor_id present" do
        assert_equal "engineer", actor_role(actor_id: 1, metadata: {})
      end

      test "actor_role job when only metadata.actor" do
        assert_equal "job", actor_role(actor_id: nil, metadata: { "actor" => "cron" })
      end

      test "actor_role anonymous when neither" do
        assert_equal "anonymous", actor_role(actor_id: nil, metadata: {})
        assert_equal "anonymous", actor_role(actor_id: nil, metadata: nil)
      end

      # ---- metadata_preview ----

      test "metadata_preview empty hash renders {}" do
        assert_includes metadata_preview({}), "{}"
        assert_includes metadata_preview(nil), "{}"
      end

      test "metadata_preview shows up to 4 keys with overflow indicator" do
        meta = {
          "ip" => "1.1.1.1", "request_id" => "req_a", "reason" => "test",
          "user_agent" => "ua", "extra" => "x"
        }
        html = metadata_preview(meta)

        assert_includes html, "ip"
        assert_includes html, "request_id"
        assert_includes html, "reason"
        assert_includes html, "user_agent"
        assert_includes html, "+1"
      end

      test "metadata_preview drops actor key (rendered separately by the actor column)" do
        meta = { "actor" => "retention_job", "ip" => "1.1.1.1" }
        html = metadata_preview(meta)

        assert_includes html, "ip"
        refute_match(/>actor</, html)
      end

      test "metadata_preview shows all 4 keys without overflow indicator" do
        meta = { "a" => 1, "b" => 2, "c" => 3, "d" => 4 }
        html = metadata_preview(meta)

        refute_match(/\+\d/, html)
      end

      # ---- mode_pill / mask_pill ----

      test "mask_pill returns nil for blank masks" do
        assert_nil mask_pill(nil)
        assert_nil mask_pill([])
      end
    end
  end
end
