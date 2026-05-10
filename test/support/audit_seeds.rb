# frozen_string_literal: true

module Athar
  module TestSupport
    module AuditSeeds
      # Default frozen "now" for deterministic time-window assertions.
      DEFAULT_NOW = Time.utc(2026, 5, 6, 14, 22, 0)

      def seed_audit_log!(now: DEFAULT_NOW) # rubocop:disable Metrics/AbcSize
        Athar::Deletion.delete_all
        Athar::TableEvent.delete_all

        rows = []

        # Mix across record types, schemas, actors, time, capture modes.
        # IDs are assigned implicitly; tests should not depend on absolute IDs.
        [
          # (record_type, schema, table, ago, actor_type, actor_id, metadata, record_data)
          [
            "User",
            "public",
            "users",
            5.minutes,
            "User",
            1,
            {
              "ip" => "1.1.1.1",
              "request_id" => "req_a"
            },
            {
              "email" => "morgan@nimbus.app",
              "name" => "Morgan"
            }
          ],
          [
            "User",
            "public",
            "users",
            1.hour,
            "User",
            27,
            {
              "ip" => "2.2.2.2",
              "request_id" => "req_b"
            },
            {
              "email" => "rae@nimbus.app",
              "name" => "Rae"
            }
          ],
          [
            "Admin",
            "public",
            "users",
            2.hours,
            "User",
            1,
            {
              "ip" => "1.1.1.1"
            },
            {
              "email" => "ad***@nimbus.app",
              "type" => "Admin"
            }
          ],
          [
            "Account",
            "public",
            "accounts",
            3.hours,
            nil,
            nil,
            {
              "actor" => "retention_job"
            },
            {}
          ],
          [
            "Subscription",
            "billing",
            "subscriptions",
            6.hours,
            nil,
            nil,
            {
              "actor" => "cron",
              "reason" => "GDPR erasure"
            },
            {}
          ],
          [
            "Session",
            "public",
            "sessions",
            8.hours,
            nil,
            nil,
            {},
            {}
          ],
          [
            "ApiToken",
            "public",
            "api_tokens",
            9.hours,
            "User",
            4,
            {
              "ip" => "3.3.3.3"
            },
            {
              "token_digest" => "*" * 56
            }
          ],
          [
            "AuditLog",
            "reporting",
            "audit_logs",
            10.hours,
            nil,
            nil,
            {
              "actor" => "retention_job"
            },
            {}
          ],
          [
            "User",
            "public",
            "users",
            2.days,
            "User",
            4,
            {
              "ip" => "4.4.4.4",
              "request_id" => "req_c"
            },
            {
              "email" => "iyana@nimbus.app",
              "name" => "Iyana"
            }
          ],
          [
            "Notification",
            "public",
            "notifications",
            5.days,
            nil,
            nil,
            {
              "actor" => "retention_job"
            },
            {}
          ],
          [
            "User",
            "public",
            "users",
            10.days,
            "User",
            27,
            {},
            {
              "email" => "old@nimbus.app",
              "name" => "Old"
            }
          ],
          [
            "User",
            "public",
            "users",
            20.days,
            "User",
            27,
            {},
            {
              "email" => "older@nimbus.app",
              "name" => "Older"
            }
          ],
          [
            "Subscription",
            "billing",
            "subscriptions",
            45.days,
            nil,
            nil,
            {
              "actor" => "cron"
            },
            {}
          ]
        ].each_with_index do |(record_type, schema, table, ago, at, aid, meta, data), i|
          rows << {
            record_type:,
            record_id: 1000 + i,
            actor_type: at,
            actor_id: aid,
            schema_name: schema,
            table_name: table,
            deleted_at: now - ago,
            created_at: now - ago,
            record_data: data,
            metadata: meta
          }
        end

        Athar::Deletion.insert_all!(rows)

        Athar::TableEvent.insert_all!(
          [
            {
              event_type: "truncate",
              schema_name: "public",
              table_name: "sessions",
              actor_type: nil,
              actor_id: nil,
              metadata: {
                "actor" => "retention_job",
                "row_count_before" => 12_345
              },
              occurred_at: now - 1.day,
              created_at: now - 1.day
            },
            {
              event_type: "truncate",
              schema_name: "public",
              table_name: "notifications",
              actor_type: nil,
              actor_id: nil,
              metadata: {
                "actor" => "retention_job"
              },
              occurred_at: now - 6.days,
              created_at: now - 6.days
            }
          ]
        )

        now
      end
    end
  end
end
