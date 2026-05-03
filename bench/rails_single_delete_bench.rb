# frozen_string_literal: true

# Local benchmark script. Not run from CI.
# Compares Rails-level single-record delete APIs with and without Athar identity capture.
#
# Usage:
#   mise run bench:rails_single

require "benchmark"
require_relative "support/audit_schema"
require_relative "support/helpers"

ITERATIONS = Bench::Helpers.env_integer("ATHAR_SINGLE_BENCH_ITERATIONS", 2_000, positive: true)
RUNS = Bench::Helpers.env_integer("ATHAR_SINGLE_BENCH_RUNS", 5, positive: true)
WARMUP_RUNS = Bench::Helpers.env_integer("ATHAR_SINGLE_BENCH_WARMUP_RUNS", 1, non_negative: true)

connection = Bench::Helpers.establish_connection!(database: "athar_single_bench")

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

def build_records(count)
  Array.new(count) do |i|
    BenchWidget.create!(email: "user#{i}@example.com", name: "Name#{i}", payload: { "k" => "v" })
  end
end

def run_once(connection, scenario) # rubocop:disable Metrics/MethodLength
  Bench::Helpers.reset_athar_session!(connection)
  connection.execute("TRUNCATE bench_widgets, athar_deletions RESTART IDENTITY")
  records = build_records(ITERATIONS)
  payload = scenario.fetch(:payload).call(records)

  Benchmark.realtime do
    payload.each do |item|
      ActiveRecord::Base.transaction do
        scenario.fetch(:action).call(item)
      end
    end
  end
ensure
  Bench::Helpers.reset_athar_session!(connection)
end

def measure(connection, scenario)
  WARMUP_RUNS.times { run_once(connection, scenario) }
  times = Array.new(RUNS) { run_once(connection, scenario) }
  scenario_stats = Bench::Helpers.stats(times, ITERATIONS)

  scenario_stats.merge(per_op_ms: (scenario_stats.fetch(:median) / ITERATIONS) * 1000)
end

delete_action = :delete.to_proc
destroy_action = :destroy!.to_proc

scenarios = [
  { label: "model.delete no trigger", trigger: false, payload: ->(records) { records }, action: delete_action },
  { label: "model.delete identity", trigger: true, payload: ->(records) { records }, action: delete_action },
  {
    label: "model.delete without_capture/call",
    trigger: true,
    payload: ->(records) { records },
    action: ->(record) { Athar.without_capture { record.delete } }
  },
  { label: "model.destroy! no trigger", trigger: false, payload: ->(records) { records }, action: destroy_action },
  { label: "model.destroy! identity", trigger: true, payload: ->(records) { records }, action: destroy_action },
  {
    label: "model.destroy! without_capture/call",
    trigger: true,
    payload: ->(records) { records },
    action: ->(record) { Athar.without_capture { record.destroy! } }
  },
  {
    label: "where.delete_all no trigger",
    trigger: false,
    payload: ->(records) { records.map(&:id) },
    action: ->(id) { BenchWidget.where(id: id).delete_all }
  },
  {
    label: "where.delete_all identity",
    trigger: true,
    payload: ->(records) { records.map(&:id) },
    action: ->(id) { BenchWidget.where(id: id).delete_all }
  },
  {
    label: "where.delete_all without_capture/call",
    trigger: true,
    payload: ->(records) { records.map(&:id) },
    action: ->(id) { Athar.without_capture { BenchWidget.where(id: id).delete_all } }
  }
]

puts "Active Record single-record delete benchmark"
puts "iterations=#{ITERATIONS}, runs=#{RUNS}, warmup_runs=#{WARMUP_RUNS}"
puts "records are created outside the timed section; each measured operation opens one transaction"
printf(
  "%<scenario>-39s %<median>10s %<ms_per_op>12s %<mean>10s %<min>10s %<max>10s %<ops_per_sec>12s\n",
  scenario: "scenario",
  median: "median",
  ms_per_op: "ms/op",
  mean: "mean",
  min: "min",
  max: "max",
  ops_per_sec: "ops/sec"
)

scenarios.each do |scenario|
  connection.execute("TRUNCATE bench_widgets, athar_deletions RESTART IDENTITY")
  install_trigger(connection, scenario.fetch(:trigger))
  scenario_stats = measure(connection, scenario)

  printf(
    "%<scenario>-39s %<median>9.3fs %<ms_per_op>11.3f %<mean>9.3fs %<min>9.3fs %<max>9.3fs %<ops_per_sec>12d\n",
    scenario: scenario.fetch(:label),
    median: scenario_stats.fetch(:median),
    ms_per_op: scenario_stats.fetch(:per_op_ms),
    mean: scenario_stats.fetch(:mean),
    min: scenario_stats.fetch(:min),
    max: scenario_stats.fetch(:max),
    ops_per_sec: scenario_stats.fetch(:rate).round
  )
end
