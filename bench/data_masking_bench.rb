# frozen_string_literal: true

# Local benchmark script. Not run from CI.
# Compares delete throughput across mask configurations.
#
# Usage:
#   mise run bench:data_masking
#
# Knobs:
#   ATHAR_BENCH_ROWS=10000
#   ATHAR_BENCH_RUNS=5
#   ATHAR_BENCH_WARMUP_RUNS=1
#   ATHAR_BENCH_INSERT_BATCH_SIZE=1000

require "benchmark"
require_relative "support/audit_schema"
require_relative "support/helpers"

ROW_COUNT    = Bench::Helpers.env_integer("ATHAR_BENCH_ROWS", 10_000, positive: true)
RUNS         = Bench::Helpers.env_integer("ATHAR_BENCH_RUNS", 5, positive: true)
WARMUP_RUNS  = Bench::Helpers.env_integer("ATHAR_BENCH_WARMUP_RUNS", 1, non_negative: true)
BATCH_SIZE   = Bench::Helpers.env_integer("ATHAR_BENCH_INSERT_BATCH_SIZE", 1_000, positive: true)

connection = Bench::Helpers.establish_connection!(database: "athar_mask_bench")

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

# Install a trigger with an explicit masks argument (TG_ARGV[8]).
# The existing AuditSchema helper omits this arg, so we build the SQL directly.
def install_masked_trigger(connection, capture_mode:, masks: nil)
  connection.execute("DROP TRIGGER IF EXISTS bench_trigger ON bench_rows")
  return if capture_mode == :none

  columns_arg = "'null'"
  masks_arg   = masks ? "'#{masks}'" : "'null'"

  connection.execute(<<~SQL)
    CREATE TRIGGER bench_trigger
    BEFORE DELETE ON bench_rows
    FOR EACH ROW
    WHEN (coalesce(current_setting('athar.disabled', true), '') <> 'on')
    EXECUTE PROCEDURE athar_capture_delete(
      'BenchRow', 'public', 'bench_rows', 'id', 'bigint', 'null',
      '#{capture_mode}', #{columns_arg}, #{masks_arg}
    );
  SQL
end

def seed!(connection, count)
  connection.execute("TRUNCATE bench_rows, athar_deletions RESTART IDENTITY")

  values = Array.new(count) do |i|
    email = connection.quote("user#{i}@example.com")
    name  = connection.quote("Name#{i}")
    "(#{email}, #{name}, '{\"k\":\"v\"}'::jsonb)"
  end
  values.each_slice(BATCH_SIZE) do |slice|
    connection.execute(
      "INSERT INTO bench_rows (email, name, payload) VALUES #{slice.join(",")}"
    )
  end
end

def run_delete_times(connection, count)
  Array.new(count) do
    seed!(connection, ROW_COUNT)
    Benchmark.realtime { connection.execute("DELETE FROM bench_rows") }
  end
end

def measure_scenario(connection, scenario)
  install_masked_trigger(
    connection,
    capture_mode: scenario.fetch(:capture_mode),
    masks: scenario[:masks]
  )
  Bench::Helpers.reset_athar_session!(connection)

  run_delete_times(connection, WARMUP_RUNS)
  times = run_delete_times(connection, RUNS)

  { times:, rows: ROW_COUNT }
ensure
  Bench::Helpers.reset_athar_session!(connection)
end

# Each scenario exercises a different mask configuration.
# Table columns available: id, email, name, payload, created_at.
SCENARIOS = [
  { label: "identity (no record_data)",     capture_mode: :identity, masks: nil },
  { label: "snapshot no masks",             capture_mode: :snapshot, masks: nil },
  { label: "snapshot 1 mask (email)",       capture_mode: :snapshot, masks: '{"email:email"}' },
  {
    label: "snapshot 3 masks",
    capture_mode: :snapshot,
    masks: '{"email:email","name:partial:1:1","payload:hash"}'
  }
].freeze

puts "Athar mask overhead benchmark (#{ROW_COUNT} rows per scenario)"
puts "runs=#{RUNS}, warmup_runs=#{WARMUP_RUNS}"
puts "-" * 74
printf(
  "  %<scenario>-30s %<median>10s %<rows_per_sec>12s %<mean>10s %<min>10s %<max>10s\n",
  scenario: "scenario",
  median: "median",
  rows_per_sec: "rows/sec",
  mean: "mean",
  min: "min",
  max: "max"
)

SCENARIOS.each do |scenario|
  result = measure_scenario(connection, scenario)
  stats  = Bench::Helpers.stats(result.fetch(:times), ROW_COUNT)

  printf(
    "  %<scenario>-30s %<median>9.3fs %<rows_per_sec>12d %<mean>9.3fs %<min>9.3fs %<max>9.3fs\n",
    scenario: scenario.fetch(:label),
    median: stats.fetch(:median),
    rows_per_sec: stats.fetch(:rate).round,
    mean: stats.fetch(:mean),
    min: stats.fetch(:min),
    max: stats.fetch(:max)
  )
end
