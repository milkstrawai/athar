# frozen_string_literal: true

# Local benchmark script. Not run from CI.
# Compares delete throughput across Athar capture modes.
#
# Usage:
#   mise run bench:delete_capture
#
# Useful knobs:
#   ATHAR_BENCH_ROWS=10000
#   ATHAR_BENCH_RUNS=5
#   ATHAR_BENCH_WARMUP_RUNS=1
#   ATHAR_BENCH_PAYLOAD_SIZE=1

require "benchmark"
require_relative "support/audit_schema"
require_relative "support/helpers"

ROW_COUNT = Bench::Helpers.env_integer("ATHAR_BENCH_ROWS", 10_000, positive: true)
RUNS = Bench::Helpers.env_integer("ATHAR_BENCH_RUNS", 5, positive: true)
WARMUP_RUNS = Bench::Helpers.env_integer("ATHAR_BENCH_WARMUP_RUNS", 1, non_negative: true)
BATCH_SIZE = Bench::Helpers.env_integer("ATHAR_BENCH_INSERT_BATCH_SIZE", 1_000, positive: true)
PAYLOAD_SIZE = Bench::Helpers.env_integer("ATHAR_BENCH_PAYLOAD_SIZE", 1, positive: true)

connection = Bench::Helpers.establish_connection!(database: "athar_bench")

connection.execute("DROP SCHEMA IF EXISTS public CASCADE")
connection.execute("CREATE SCHEMA public")

connection.execute(<<~SQL)
  CREATE TABLE bench_rows (
    id bigserial PRIMARY KEY,
    email text,
    name text,
    payload jsonb DEFAULT '{}'::jsonb,
    created_at timestamp DEFAULT statement_timestamp()
  );
SQL

Bench::AuditSchema.install!(connection)

def install_trigger(connection, mode, columns: nil)
  Bench::AuditSchema.install_delete_trigger(
    connection,
    trigger_name: "bench_trigger",
    table_name: "bench_rows",
    record_type: "BenchRow",
    capture_mode: mode,
    columns:
  )
end

def seed!(connection, count)
  connection.execute("TRUNCATE bench_rows, athar_deletions RESTART IDENTITY")
  payload = connection.quote({ "k" => "v" * PAYLOAD_SIZE }.to_json)

  values = Array.new(count) do |i|
    email = connection.quote("user#{i}@example.com")
    name = connection.quote("Name#{i}")
    "(#{email}, #{name}, #{payload}::jsonb)"
  end
  values.each_slice(BATCH_SIZE) do |slice|
    connection.execute(
      "INSERT INTO bench_rows (email, name, payload) VALUES #{slice.join(",")}"
    )
  end
end

def apply_metadata(connection, metadata)
  if metadata
    connection.execute("SET athar.meta = #{connection.quote(metadata.to_json)}")
  else
    connection.execute("RESET athar.meta")
  end
end

def apply_disabled(connection, disabled)
  if disabled
    connection.execute("SET athar.disabled = 'on'")
  else
    connection.execute("RESET athar.disabled")
  end
end

def run_delete_times(connection, count)
  Array.new(count) do
    seed!(connection, ROW_COUNT)
    Benchmark.realtime { connection.execute("DELETE FROM bench_rows") }
  end
end

def measure_scenario(connection, scenario)
  install_trigger(
    connection,
    scenario.fetch(:mode),
    columns: scenario[:columns]
  )
  Bench::Helpers.reset_athar_session!(connection)
  apply_metadata(connection, scenario[:metadata])
  apply_disabled(connection, scenario[:disabled])

  warmup_times = run_delete_times(connection, WARMUP_RUNS)
  times = run_delete_times(connection, RUNS)

  {
    warmup_times:,
    times:,
    rows: ROW_COUNT
  }
ensure
  Bench::Helpers.reset_athar_session!(connection)
end

scenarios = [
  { label: "no trigger", mode: :none },
  { label: "disabled trigger", mode: :identity, disabled: true },
  { label: "identity capture", mode: :identity },
  { label: "identity + metadata", mode: :identity, metadata: { request_id: "req-1", source: "bench" } },
  { label: "only capture", mode: :only, columns: %w[email name] },
  { label: "snapshot capture", mode: :snapshot }
]

puts "Athar delete capture benchmark (#{ROW_COUNT} rows per scenario)"
puts "runs=#{RUNS}, warmup_runs=#{WARMUP_RUNS}, payload_size=#{PAYLOAD_SIZE}"
puts "-" * 64
printf(
  "  %<scenario>-22s %<median>10s %<rows_per_sec>12s %<mean>10s %<min>10s %<max>10s\n",
  scenario: "scenario",
  median: "median",
  rows_per_sec: "rows/sec",
  mean: "mean",
  min: "min",
  max: "max"
)

scenarios.each do |scenario|
  result = measure_scenario(connection, scenario)
  scenario_stats = Bench::Helpers.stats(result.fetch(:times), ROW_COUNT)

  printf(
    "  %<scenario>-22s %<median>9.3fs %<rows_per_sec>12d %<mean>9.3fs %<min>9.3fs %<max>9.3fs\n",
    scenario: scenario.fetch(:label),
    median: scenario_stats.fetch(:median),
    rows_per_sec: scenario_stats.fetch(:rate).round,
    mean: scenario_stats.fetch(:mean),
    min: scenario_stats.fetch(:min),
    max: scenario_stats.fetch(:max)
  )
end
