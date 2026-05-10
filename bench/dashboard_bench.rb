# frozen_string_literal: true

# Dashboard query benchmark.
#
# Seeds athar_deletions + athar_table_events with a realistic distribution
# (~1M deletions by default), then runs each dashboard query under
# representative filter combinations and prints EXPLAIN (ANALYZE, BUFFERS)
# timings.
#
# Usage:
#   mise run bench:dashboard
#
# Knobs:
#   ATHAR_BENCH_DELETION_ROWS=1000000
#   ATHAR_BENCH_TABLE_EVENT_ROWS=5000
#   ATHAR_BENCH_BATCH_SIZE=10000
#   ATHAR_BENCH_RESEED=1    # force re-seed even if row count looks right
#   ATHAR_BENCH_SKIP_SEED=1 # skip seed entirely (re-use existing data)

require "json"
require "securerandom"
require_relative "support/audit_schema"
require_relative "support/helpers"

DELETION_ROWS = Bench::Helpers.env_integer("ATHAR_BENCH_DELETION_ROWS", 1_000_000, positive: true)
TABLE_EVENT_ROWS = Bench::Helpers.env_integer("ATHAR_BENCH_TABLE_EVENT_ROWS", 5_000, positive: true)
BATCH_SIZE = Bench::Helpers.env_integer("ATHAR_BENCH_BATCH_SIZE", 10_000, positive: true)
RESEED = ENV["ATHAR_BENCH_RESEED"] == "1"
SKIP_SEED = ENV["ATHAR_BENCH_SKIP_SEED"] == "1"

connection = Bench::Helpers.establish_connection!(database: "athar_dashboard_bench")

# ---------- schema ----------
if !SKIP_SEED && (RESEED ||
     !connection.table_exists?("athar_deletions") ||
     connection.select_value("SELECT COUNT(*) FROM athar_deletions").to_i != DELETION_ROWS)
  puts "[bench] (re)building schema in athar_dashboard_bench…"
  connection.execute("DROP TABLE IF EXISTS athar_deletions, athar_table_events CASCADE")
  Bench::AuditSchema.install!(connection)
end

# ---------- seed data ----------
RECORD_TYPES = [
  ["Comment", "public", "comments", 0.45],
  ["User", "public", "users", 0.20],
  ["SmallCounter", "public", "small_counters", 0.10],
  ["Account", "public", "accounts", 0.05],
  ["LegacyToken", "public", "legacy_tokens", 0.05],
  ["ApiClient", "public", "api_clients", 0.04],
  ["SessionRecord", "public", "session_records", 0.06],
  ["Reporting::Bucket", "reporting", "reporting_buckets", 0.05]
].freeze

USER_ACTOR_TYPES = %w[User Admin Operator].freeze
SYSTEM_ACTORS = %w[retention_job cron ops_console].freeze
REASONS = ["GDPR erasure request", "user requested deletion", "scheduled retention", "consent revoked", nil].freeze

def pick_weighted(rows)
  total = rows.sum { |row| row[3] }
  threshold = rand * total
  cumulative = 0
  rows.each do |row|
    cumulative += row[3]
    return row if cumulative >= threshold
  end
  rows.last
end

def build_deletion_row(idx, now) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
  record_type, schema, table, = pick_weighted(RECORD_TYPES)

  # Time skew: 60% in last 30d, 30% in last 60d, 10% older. Within each band,
  # uniform. This biases the dashboard's default 30d window toward typical
  # production traffic shape.
  age_seconds =
    case rand
    when 0..0.6 then rand(0..(30 * 86_400))
    when 0..0.9 then (30 * 86_400) + rand(0..(30 * 86_400))
    else (60 * 86_400) + rand(0..(30 * 86_400))
    end
  deleted_at = now - age_seconds

  case rand
  when 0..0.6
    # User actor
    actor_type = USER_ACTOR_TYPES.sample
    actor_id = rand(1..500)
    metadata = {
      "ip" => "10.0.#{rand(256)}.#{rand(256)}",
      "request_id" => "req_#{SecureRandom.hex(4)}",
      "reason" => REASONS.sample
    }.compact
  when 0..0.9
    # System actor (no actor_id, metadata.actor set)
    actor_type = nil
    actor_id = nil
    metadata = { "actor" => SYSTEM_ACTORS.sample }
    metadata["reason"] = REASONS.sample if rand < 0.5
  else
    # Truly anonymous
    actor_type = nil
    actor_id = nil
    metadata = {}
  end

  record_data = rand < 0.3 ? { "email" => "user#{idx % 100}@example.com" } : {}

  {
    record_type: record_type,
    record_id: 1000 + idx,
    actor_type: actor_type,
    actor_id: actor_id,
    schema_name: schema,
    table_name: table,
    deleted_at: deleted_at,
    created_at: deleted_at,
    record_data: JSON.dump(record_data),
    metadata: JSON.dump(metadata)
  }
end

def build_table_event_row(now)
  _, schema, table, = pick_weighted(RECORD_TYPES)
  age_seconds = rand(0..(60 * 86_400))
  occurred_at = now - age_seconds

  {
    event_type: "truncate",
    schema_name: schema,
    table_name: table,
    actor_type: nil,
    actor_id: nil,
    metadata: JSON.dump({ "actor" => SYSTEM_ACTORS.sample, "row_count_before" => rand(100..50_000) }),
    occurred_at: occurred_at,
    created_at: occurred_at
  }
end

class BenchDeletion < ActiveRecord::Base
  self.table_name = "athar_deletions"
end

class BenchTableEvent < ActiveRecord::Base # rubocop:disable Style/OneClassPerFile
  self.table_name = "athar_table_events"
end

if !SKIP_SEED && (RESEED || connection.select_value("SELECT COUNT(*) FROM athar_deletions").to_i != DELETION_ROWS)
  now = Time.now.utc
  print "[bench] seeding #{DELETION_ROWS} deletions"
  $stdout.flush

  seeded = 0
  while seeded < DELETION_ROWS
    n = [BATCH_SIZE, DELETION_ROWS - seeded].min
    rows = Array.new(n) { |i| build_deletion_row(seeded + i, now) }
    BenchDeletion.insert_all!(rows)
    seeded += n
    print "."
    $stdout.flush
  end
  puts " done (#{seeded})"

  print "[bench] seeding #{TABLE_EVENT_ROWS} table_events… "
  $stdout.flush
  rows = Array.new(TABLE_EVENT_ROWS) { build_table_event_row(now) }
  rows.each_slice(BATCH_SIZE) { |batch| BenchTableEvent.insert_all!(batch) }
  puts "done"

  print "[bench] VACUUM ANALYZE… "
  $stdout.flush
  connection.execute("VACUUM ANALYZE athar_deletions")
  connection.execute("VACUUM ANALYZE athar_table_events")
  puts "done"
end

deletions_total = connection.select_value("SELECT COUNT(*) FROM athar_deletions").to_i
table_events_total = connection.select_value("SELECT COUNT(*) FROM athar_table_events").to_i
puts "[bench] dataset: #{deletions_total} deletions, #{table_events_total} table_events"

# ---------- dashboard query setup ----------
require_relative "../lib/athar"
Athar::DELETIONS_TABLE_NAME = "athar_deletions" unless Athar.const_defined?(:DELETIONS_TABLE_NAME)
Athar::TABLE_EVENTS_TABLE_NAME = "athar_table_events" unless Athar.const_defined?(:TABLE_EVENTS_TABLE_NAME)
require_relative "../lib/athar/dashboard"

NOW = Time.now.utc

def filters(model: nil, time: "30d", mode: "all", kind: "all", actor: "all", query: "", page: 1) # rubocop:disable Metrics/ParameterLists
  Athar::Dashboard::FilterSet.new(
    model: model, time: time, mode: mode, kind: kind, actor: actor,
    query: query, page: page, expanded: nil
  )
end

# Empty registry — model filter on table_events would 0-out via FALSE; we test
# only deletion-side scenarios so a real registry isn't necessary for these
# benchmarks. Provide [] so methods don't try to discover from pg_trigger.
EMPTY_REGISTRY = [].freeze

def time_query(connection, label, sql) # rubocop:disable Metrics/AbcSize
  # Warm cache once, then EXPLAIN ANALYZE.
  connection.execute(sql)
  plan = connection.exec_query("EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) #{sql}").rows.first.first
  parsed = plan.is_a?(String) ? JSON.parse(plan) : plan
  root = parsed.first["Plan"]
  total = root["Actual Total Time"]
  rows = root["Actual Rows"]
  buffers = root["Shared Hit Blocks"].to_i + root["Shared Read Blocks"].to_i
  scan = describe_scan(root)
  printf(
    "  %<label>-50s %<total>8.2f ms  rows=%<rows>-7d  buffers=%<buffers>-6d  %<scan>s\n",
    label: label,
    total: total,
    rows: rows,
    buffers: buffers,
    scan: scan
  )
end

def describe_scan(node, depth = 0) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
  return "" if depth > 4

  node_type = node["Node Type"]
  index = node["Index Name"]
  extras = []
  extras << index if index
  extras << "rel=#{node["Relation Name"]}" if node["Relation Name"]
  result = "#{node_type}#{"(#{extras.join(",")})" unless extras.empty?}"

  children = node["Plans"] || []
  children_desc = children.map { |c| describe_scan(c, depth + 1) }.reject(&:empty?).first(2).join(" / ")
  children_desc.empty? ? result : "#{result} ← #{children_desc}"
end

def feed_sql(filters_obj, count: false)
  fq = Athar::Dashboard::FeedQuery.new(filters: filters_obj, per_page: 25, now: NOW, registry: EMPTY_REGISTRY)
  fq.send(count ? :count_sql : :page_sql)
end

def kpi_sql(model) # rubocop:disable Metrics/AbcSize
  q = ->(value) { ActiveRecord::Base.connection.quote(value) }
  scope = model ? "WHERE record_type = #{q.call(model)}" : ""
  <<~SQL
    SELECT
      COUNT(*) AS scope_total,
      COUNT(*) FILTER (WHERE deleted_at > #{q.call(NOW - (1 * 86_400))}) AS last_24h,
      COUNT(*) FILTER (WHERE deleted_at > #{q.call(NOW - (7 * 86_400))}) AS last_7d,
      COUNT(*) FILTER (WHERE deleted_at > #{q.call(NOW - (14 * 86_400))} AND deleted_at <= #{q.call(NOW - (7 * 86_400))}) AS prior_7d,
      COUNT(DISTINCT (actor_type, actor_id))
        FILTER (WHERE actor_id IS NOT NULL AND deleted_at > #{q.call(NOW - (30 * 86_400))}) AS distinct_actors_30d
    FROM athar_deletions
    #{scope}
  SQL
end

def sparkline_sql(model)
  q = ->(value) { ActiveRecord::Base.connection.quote(value) }
  scope = model ? "AND record_type = #{q.call(model)}" : ""
  <<~SQL
    SELECT date_trunc('day', deleted_at) AS day, COUNT(*) AS n
    FROM athar_deletions
    WHERE deleted_at > #{q.call(NOW - (14 * 86_400))} #{scope}
    GROUP BY day ORDER BY day
  SQL
end

def actor_users_sql
  q = ->(value) { ActiveRecord::Base.connection.quote(value) }
  <<~SQL
    SELECT actor_type, actor_id::text AS actor_id, MAX(deleted_at) AS last_seen
    FROM athar_deletions
    WHERE actor_id IS NOT NULL AND deleted_at >= #{q.call(NOW - (30 * 86_400))}
    GROUP BY actor_type, actor_id
    ORDER BY last_seen DESC
    LIMIT 50
  SQL
end

def actor_system_sql
  q = ->(value) { ActiveRecord::Base.connection.quote(value) }
  <<~SQL
    SELECT metadata->>'actor' AS name, MAX(deleted_at) AS last_seen
    FROM athar_deletions
    WHERE actor_id IS NULL AND metadata ? 'actor' AND deleted_at >= #{q.call(NOW - (30 * 86_400))}
    GROUP BY 1
    ORDER BY last_seen DESC
    LIMIT 50
  SQL
end

# ---------- run benchmarks ----------
puts "\n[bench] dashboard queries (cache-warmed; EXPLAIN ANALYZE, BUFFERS)\n"

scenarios = [
  ["FeedQuery#page no filter (30d)",        feed_sql(filters)],
  ["FeedQuery#page model=Comment",          feed_sql(filters(model: "Comment"))],
  ["FeedQuery#page time=24h",               feed_sql(filters(time: "24h"))],
  ["FeedQuery#page time=all",               feed_sql(filters(time: "all"))],
  ["FeedQuery#page actor=user:User:42",     feed_sql(filters(actor: "user:User:42"))],
  ["FeedQuery#page actor=anon",             feed_sql(filters(actor: "anon"))],
  ["FeedQuery#page actor=sys:retention_job", feed_sql(filters(actor: "sys:retention_job"))],
  ["FeedQuery#page q=req_a",                feed_sql(filters(query: "req_a"))],
  ["FeedQuery#page page=100",               feed_sql(filters(page: 100))],
  ["FeedQuery#total no filter",             feed_sql(filters, count: true)],
  ["FeedQuery#total model=Comment",         feed_sql(filters(model: "Comment"), count: true)],
  ["KpiCalculator no model",                kpi_sql(nil)],
  ["KpiCalculator model=Comment",           kpi_sql("Comment")],
  ["Sparkline no model",                    sparkline_sql(nil)],
  ["Sparkline model=Comment",               sparkline_sql("Comment")],
  ["ActorOptions users",                    actor_users_sql],
  ["ActorOptions system",                   actor_system_sql]
]

scenarios.each do |label, sql|
  time_query(connection, label, sql)
rescue StandardError => e
  printf("  %<label>-50s ERROR: %<message>s\n", label: label, message: e.message)
end
