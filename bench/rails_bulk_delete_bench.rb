# frozen_string_literal: true

# Local benchmark script. Not run from CI.
# Compares Rails-level bulk delete APIs with and without Athar identity capture.
#
# Usage:
#   mise run bench:rails_bulk

require "benchmark"
require_relative "support/audit_schema"
require_relative "support/helpers"

DELETE_ALL_ROWS = Bench::Helpers.env_integer("ATHAR_RAILS_BENCH_DELETE_ALL_ROWS", 10_000, positive: true)
DESTROY_ALL_ROWS = Bench::Helpers.env_integer("ATHAR_RAILS_BENCH_DESTROY_ALL_ROWS", 1_000, positive: true)
RUNS = Bench::Helpers.env_integer("ATHAR_RAILS_BENCH_RUNS", 5, positive: true)
WARMUP_RUNS = Bench::Helpers.env_integer("ATHAR_RAILS_BENCH_WARMUP_RUNS", 1, non_negative: true)
BATCH_SIZE = Bench::Helpers.env_integer("ATHAR_RAILS_BENCH_INSERT_BATCH_SIZE", 1_000, positive: true)

connection = Bench::Helpers.establish_connection!(database: "athar_rails_bench")

connection.execute("DROP SCHEMA IF EXISTS public CASCADE")
connection.execute("CREATE SCHEMA public")

connection.execute(<<~SQL)
  CREATE TABLE bench_widgets (
    id bigserial PRIMARY KEY,
    email text,
    name text,
    payload jsonb DEFAULT '{}'::jsonb,
    created_at timestamp DEFAULT statement_timestamp(),
    updated_at timestamp DEFAULT statement_timestamp()
  );
SQL

Bench::AuditSchema.install!(connection)

class BenchWidget < ActiveRecord::Base
  self.table_name = "bench_widgets"
end

BenchWidget.reset_column_information

def install_trigger(connection, enabled)
  mode = enabled ? :identity : :none
  Bench::AuditSchema.install_delete_trigger(
    connection,
    trigger_name: "bench_widgets_athar",
    table_name: "bench_widgets",
    record_type: "BenchWidget",
    capture_mode: mode
  )
end

def seed!(connection, count)
  connection.execute("TRUNCATE bench_widgets, athar_deletions RESTART IDENTITY")
  values = Array.new(count) do |i|
    email = connection.quote("user#{i}@example.com")
    name = connection.quote("Name#{i}")
    "(#{email}, #{name}, '{\"k\":\"v\"}'::jsonb)"
  end
  values.each_slice(BATCH_SIZE) do |slice|
    connection.execute("INSERT INTO bench_widgets (email, name, payload) VALUES #{slice.join(",")}")
  end
end

def run_times(connection, count, &block) # rubocop:disable Metrics/MethodLength
  Array.new(WARMUP_RUNS) do
    Bench::Helpers.reset_athar_session!(connection)
    seed!(connection, count)
    ActiveRecord::Base.transaction { block.call }
    Bench::Helpers.reset_athar_session!(connection)
  end

  Array.new(RUNS) do
    Bench::Helpers.reset_athar_session!(connection)
    seed!(connection, count)
    Benchmark.realtime { ActiveRecord::Base.transaction { block.call } }
  ensure
    Bench::Helpers.reset_athar_session!(connection)
  end
end

scenarios = [
  { label: "delete_all no trigger", rows: DELETE_ALL_ROWS, trigger: false, action: -> { BenchWidget.delete_all } },
  { label: "delete_all identity", rows: DELETE_ALL_ROWS, trigger: true, action: -> { BenchWidget.delete_all } },
  {
    label: "delete_all without_capture",
    rows: DELETE_ALL_ROWS,
    trigger: true,
    action: -> { Athar.without_capture { BenchWidget.delete_all } }
  },
  { label: "destroy_all no trigger", rows: DESTROY_ALL_ROWS, trigger: false, action: -> { BenchWidget.destroy_all } },
  { label: "destroy_all identity", rows: DESTROY_ALL_ROWS, trigger: true, action: -> { BenchWidget.destroy_all } },
  {
    label: "destroy_all without_capture",
    rows: DESTROY_ALL_ROWS,
    trigger: true,
    action: -> { Athar.without_capture { BenchWidget.destroy_all } }
  }
]

puts "Active Record bulk delete benchmark"
puts "delete_all_rows=#{DELETE_ALL_ROWS}, destroy_all_rows=#{DESTROY_ALL_ROWS}, runs=#{RUNS}, warmup_runs=#{WARMUP_RUNS}" # rubocop:disable Layout/LineLength
puts "each measured delete/destroy action runs inside one outer transaction"
printf(
  "%<scenario>-34s %<median>8s %<rows_per_sec>10s %<mean>10s %<min>10s %<max>10s\n",
  scenario: "scenario",
  median: "median",
  rows_per_sec: "rows/sec",
  mean: "mean",
  min: "min",
  max: "max"
)

scenarios.each do |scenario|
  install_trigger(connection, scenario.fetch(:trigger))
  times = run_times(connection, scenario.fetch(:rows), &scenario.fetch(:action))
  scenario_stats = Bench::Helpers.stats(times, scenario.fetch(:rows))

  printf(
    "%<scenario>-34s %<median>7.3fs %<rows_per_sec>10d %<mean>9.3fs %<min>9.3fs %<max>9.3fs\n",
    scenario: scenario.fetch(:label),
    median: scenario_stats.fetch(:median),
    rows_per_sec: scenario_stats.fetch(:rate).round,
    mean: scenario_stats.fetch(:mean),
    min: scenario_stats.fetch(:min),
    max: scenario_stats.fetch(:max)
  )
end
