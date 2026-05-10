# frozen_string_literal: true

require "test_helper"

module Athar
  class DashboardControllerTest < ActionDispatch::IntegrationTest # rubocop:disable Metrics/ClassLength
    test "GET / renders 200" do
      get "/athar"

      assert_response :success
    end

    test "renders the dashboard wrapper div" do
      get "/athar"

      assert_includes response.body, %(<div id="athar-dashboard")
    end

    test "renders sidebar models from registry" do
      seed_audit_log!
      get "/athar"

      assert_includes response.body, "User"
    end

    test "filter by model scopes the table" do
      seed_audit_log!
      get "/athar", params: { model: "Subscription" }

      # Only the recent Subscription deletion (6h ago, metadata.reason="GDPR erasure")
      # is in the 30d window — User/Admin/Session/etc. rows must be filtered out.
      assert_includes response.body, "GDPR erasure"
      refute_match(/req_a|req_b|req_c/, response.body)
      refute_match(/no audit rows match/, response.body)
    end

    test "kind=truncate filters table" do
      seed_audit_log!
      get "/athar", params: { kind: "truncate" }

      refute_match(/morgan@nimbus.app/, response.body) # row data shouldn't appear
    end

    test "search by metadata key matches only that row" do
      seed_audit_log!
      get "/athar", params: { q: "req_a" }

      assert_response :success
      # req_a is morgan's request_id; req_b (rae) and req_c (iyana) must be filtered out.
      refute_match(/req_b|req_c/, response.body)
      refute_match(/no audit rows match/, response.body)
    end

    test "out-of-range page renders the empty state" do
      seed_audit_log!
      get "/athar", params: { page: 99 }

      assert_response :success
      assert_includes response.body, "no audit rows match"
    end

    test "sidebar renders schema groupings" do
      seed_audit_log!
      get "/athar"

      assert_includes response.body, "public"
      assert_includes response.body, "All deletions"
    end

    test "topbar renders breadcrumbs and connection info" do
      seed_audit_log!
      get "/athar"

      assert_includes response.body, "athar"
      assert_includes response.body, "deletions"
      assert_includes response.body, "conn-pill"
      assert_match(/pg\d+/, response.body)
    end

    test "kpi strip renders six cards" do
      seed_audit_log!
      get "/athar"

      assert_includes response.body, "kpi-strip"
      assert_includes response.body, "filtered rows"
      assert_includes response.body, "deletions · 14d"
    end

    test "filter bar renders search and segments" do
      seed_audit_log!
      get "/athar"

      assert_includes response.body, %(name="q")
      assert_includes response.body, "30d"
      assert_includes response.body, %(name="actor")
    end

    test "pager renders range and buttons" do
      seed_audit_log!
      get "/athar"

      assert_includes response.body, "pager"
      assert_includes response.body, "page"
    end

    test "table renders deleted_at and record cells" do
      seed_audit_log!
      get "/athar"

      assert_match(/m ago|h ago|d ago|s ago/, response.body)
      assert_includes response.body, "kind-icon"
    end

    test "expanded inline shows detail" do
      seed_audit_log!
      d = Athar::Deletion.first
      get "/athar", params: { expanded: d.id, time: "all" }

      assert_includes response.body, "record_data"
      assert_includes response.body, "drow-detail"
    end

    test "table empty state renders when no rows" do
      Athar::Deletion.delete_all
      Athar::TableEvent.delete_all
      get "/athar"

      assert_includes response.body, "no audit rows match"
    end

    test "layout includes dashboard stylesheet link" do
      get "/athar"

      assert_match(%r{athar/dashboard}, response.body)
    end

    test "combining model + time + actor narrows to a single row" do
      seed_audit_log!
      get "/athar", params: { model: "User", time: "7d", actor: "user:User:1", mode: "all" }

      assert_response :success
      # Only morgan (User deletion, User#1 actor, 5min ago) survives.
      # Admin#1 deletion is excluded by record_type=User, others by actor.
      assert_match(/req_a/, response.body)              # morgan's metadata
      refute_match(/req_b|req_c/, response.body)        # rae (User#27), iyana (User#4)
      refute_match(/no audit rows match/, response.body)
    end

    test "search with no matches renders the empty state" do
      seed_audit_log!
      get "/athar", params: { q: "definitely-no-match-string" }

      assert_response :success
      assert_includes response.body, "no audit rows match"
    end

    test "actor=anon scopes to anonymous rows" do
      seed_audit_log!
      get "/athar", params: { actor: "anon", time: "all" }

      assert_response :success
      # Only the Session deletion qualifies as anon (actor_id NULL, no metadata.actor).
      assert_match(/actor-anonymous/, response.body)
      refute_match(/actor-engineer/, response.body)     # no User actors
      refute_match(/actor-job/, response.body)          # no sys actors
      refute_match(/req_a|req_b|req_c/, response.body)  # no User-actor metadata
      refute_match(/no audit rows match/, response.body)
    end

    test "actor=sys:retention_job scopes to system rows" do
      seed_audit_log!
      get "/athar", params: { actor: "sys:retention_job", time: "all" }

      assert_response :success
      assert_match(/actor-job/, response.body)
      refute_match(/actor-engineer/, response.body)     # no User actors
      refute_match(/actor-anonymous/, response.body)    # no anon rows
      refute_match(/req_a|req_b|req_c/, response.body)
      refute_match(/no audit rows match/, response.body)
    end

    test "page query param renders the requested page in the pager" do
      seed_audit_log!
      get "/athar", params: { page: 2, time: "all" }

      assert_response :success
      # 15 seeded rows fit on a single 25-row page, so page 2 is empty —
      # but the pager must reflect current=2 regardless.
      assert_match(%r{<span class="pager-page">page <span class="mono">2</span>}, response.body)
    end

    # End-to-end coverage for hosts that set
    # `Rails.configuration.generators.options[:active_record][:primary_key_type] = :uuid`,
    # which makes the install migration create the audit tables with uuid ids.
    # Each kind filter is exercised so both UNION legs (live + empty placeholder)
    # are typed consistently, regardless of the host's primary-key choice.
    test "dashboard renders against uuid-id audit tables across kind filters" do
      with_uuid_audit_tables do
        deletion_id = SecureRandom.uuid
        truncate_id = SecureRandom.uuid
        now = Time.current

        Athar::Deletion.insert_all!(
          [
            { id: deletion_id, record_type: "User", record_id: SecureRandom.uuid,
              actor_type: nil, actor_id: nil,
              schema_name: "public", table_name: "users",
              deleted_at: now, created_at: now,
              record_data: { email: "uuid-row@nimbus.app" }, metadata: {} }
          ]
        )

        Athar::TableEvent.insert_all!(
          [
            { id: truncate_id, event_type: "truncate",
              schema_name: "public", table_name: "sessions",
              actor_type: nil, actor_id: nil,
              occurred_at: now - 1.hour, created_at: now - 1.hour,
              metadata: {} }
          ]
        )

        get "/athar", params: { kind: "delete", time: "all" }

        assert_response :success
        assert_includes response.body, deletion_id
        refute_includes response.body, truncate_id

        get "/athar", params: { kind: "truncate", time: "all" }

        assert_response :success
        assert_includes response.body, truncate_id
        refute_includes response.body, deletion_id

        get "/athar", params: { time: "all" }

        assert_response :success
        assert_includes response.body, deletion_id
        assert_includes response.body, truncate_id
      end
    end
  end
end
