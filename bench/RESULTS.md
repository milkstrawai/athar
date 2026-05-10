# Benchmark Baseline

These numbers are anchors, not targets. Numbers are heavily machine-, kernel-, and PostgreSQL-version dependent. Treat them as a regression sanity check.

The benchmark scripts rebuild a dedicated database schema, install Athar's SQL functions, and create production-like audit indexes. They are destructive and should only run against throwaway benchmark databases.

Run the SQL-level bulk benchmark with:

```sh
mise run bench:delete_capture
```

Run the Rails bulk benchmark with:

```sh
mise run bench:rails_bulk
```

Run the Rails single-record benchmark with:

```sh
mise run bench:rails_single
```

Run the data-masking overhead benchmark with:

```sh
mise run bench:data_masking
```

Run the dashboard query benchmark with:

```sh
mise run bench:dashboard
```

The mise tasks start the local Docker Compose PostgreSQL service when needed, create the throwaway benchmark database, run the benchmark, and stop only the service they started.

Useful SQL benchmark knobs:

- `ATHAR_BENCH_ROWS`: rows deleted per measured run. Default: `10000`.
- `ATHAR_BENCH_RUNS`: measured runs per scenario. Default: `5`.
- `ATHAR_BENCH_WARMUP_RUNS`: warmup runs before measurement. Default: `1`.
- `ATHAR_BENCH_PAYLOAD_SIZE`: size multiplier for the JSONB payload value. Default: `1`.
- `ATHAR_BENCH_INSERT_BATCH_SIZE`: insert batch size used while reseeding. Default: `1000`.

Useful Rails bulk benchmark knobs:

- `ATHAR_RAILS_BENCH_DELETE_ALL_ROWS`: rows per `delete_all` run. Default: `10000`.
- `ATHAR_RAILS_BENCH_DESTROY_ALL_ROWS`: rows per `destroy_all` run. Default: `1000`.
- `ATHAR_RAILS_BENCH_RUNS`: measured runs per scenario. Default: `5`.
- `ATHAR_RAILS_BENCH_WARMUP_RUNS`: warmup runs before measurement. Default: `1`.

Useful Rails single-record benchmark knobs:

- `ATHAR_SINGLE_BENCH_ITERATIONS`: measured single-row operations per scenario. Default: `2000`.
- `ATHAR_SINGLE_BENCH_RUNS`: measured runs per scenario. Default: `5`.
- `ATHAR_SINGLE_BENCH_WARMUP_RUNS`: warmup runs before measurement. Default: `1`.

Useful data-masking benchmark knobs:

- `ATHAR_BENCH_ROWS`: rows deleted per measured run. Default: `10000`.
- `ATHAR_BENCH_RUNS`: measured runs per scenario. Default: `5`.
- `ATHAR_BENCH_WARMUP_RUNS`: warmup runs before measurement. Default: `1`.
- `ATHAR_BENCH_INSERT_BATCH_SIZE`: insert batch size used while reseeding. Default: `1000`.

Useful dashboard benchmark knobs:

- `ATHAR_BENCH_DELETION_ROWS`: rows seeded into `athar_deletions`. Default: `1000000`.
- `ATHAR_BENCH_TABLE_EVENT_ROWS`: rows seeded into `athar_table_events`. Default: `5000`.
- `ATHAR_BENCH_BATCH_SIZE`: insert batch size while seeding. Default: `10000`.
- `ATHAR_BENCH_RESEED=1`: force a fresh seed even if the row count already matches.
- `ATHAR_BENCH_SKIP_SEED=1`: skip seeding entirely and benchmark against existing data.

## Environment

- Date: 2026-05-10
- Hardware: Apple Silicon, macOS 26.2, Docker
- PostgreSQL: 18.3 (Debian 18.3-1.pgdg13+1), `postgres:18`
- Ruby: 4.0.3

## SQL Bulk Delete

- Rows per scenario: 10,000
- Runs: 5
- Warmup runs: 1
- Payload size: 1
- Audit indexes: yes

| Scenario            | Median | Rows/sec |   Mean |    Min |    Max |
| ------------------- | -----: | -------: | -----: | -----: | -----: |
| no trigger          | 0.003s | 3,759,398 | 0.003s | 0.003s | 0.003s |
| disabled trigger    | 0.005s | 1,885,370 | 0.005s | 0.005s | 0.006s |
| identity capture    | 0.234s |   42,665 | 0.236s | 0.220s | 0.248s |
| identity + metadata | 0.242s |   41,396 | 0.270s | 0.232s | 0.384s |
| only capture        | 0.250s |   39,920 | 0.257s | 0.239s | 0.293s |
| snapshot capture    | 0.230s |   43,515 | 0.231s | 0.223s | 0.243s |

## Rails Bulk Delete

- `delete_all` rows per scenario: 10,000
- `destroy_all` rows per scenario: 1,000
- Runs: 5
- Warmup runs: 1
- Audit indexes: yes
- Each measured delete/destroy action runs inside one outer transaction.

| Scenario              | Median | Rows/sec |   Mean |    Min |    Max |
| --------------------- | -----: | -------: | -----: | -----: | -----: |
| `delete_all` no trigger | 0.004s | 2,376,426 | 0.005s | 0.003s | 0.010s |
| `delete_all` identity | 0.241s |   41,564 | 0.262s | 0.234s | 0.358s |
| `delete_all` without_capture | 0.007s | 1,390,047 | 0.007s | 0.007s | 0.008s |
| `destroy_all` no trigger | 0.440s |    2,271 | 0.500s | 0.407s | 0.784s |
| `destroy_all` identity | 0.528s |    1,892 | 0.541s | 0.492s | 0.584s |
| `destroy_all` without_capture | 0.476s |    2,100 | 0.482s | 0.436s | 0.542s |

## Rails Single-Record Delete

- Iterations per scenario: 2,000
- Runs: 5
- Warmup runs: 1
- Records are created outside the timed section.
- Each measured operation opens one transaction.
- Audit indexes: yes

| Scenario | Median | Ms/op |   Mean |    Min |    Max | Ops/sec |
| -------- | -----: | ----: | -----: | -----: | -----: | ------: |
| `model.delete` no trigger | 1.609s | 0.804 | 1.723s | 1.544s | 2.020s | 1,243 |
| `model.delete` identity | 2.195s | 1.098 | 2.230s | 2.075s | 2.430s |   911 |
| `model.delete` without_capture/call | 3.065s | 1.533 | 3.054s | 2.643s | 3.527s |   653 |
| `model.destroy!` no trigger | 1.975s | 0.987 | 1.999s | 1.820s | 2.273s | 1,013 |
| `model.destroy!` identity | 2.465s | 1.233 | 2.443s | 2.243s | 2.623s |   811 |
| `model.destroy!` without_capture/call | 3.170s | 1.585 | 3.230s | 2.901s | 3.697s |   631 |
| `where(id:).delete_all` no trigger | 1.934s | 0.967 | 2.031s | 1.725s | 2.628s | 1,034 |
| `where(id:).delete_all` identity | 2.454s | 1.227 | 2.448s | 2.288s | 2.604s |   815 |
| `where(id:).delete_all` without_capture/call | 2.999s | 1.499 | 2.994s | 2.775s | 3.205s |   667 |

## Data Masking

- Rows per scenario: 10,000
- Runs: 5
- Warmup runs: 1
- Audit indexes: yes
- Capture mode: snapshot, except where noted

| Scenario                  | Median | Rows/sec |   Mean |    Min |    Max |
| ------------------------- | -----: | -------: | -----: | -----: | -----: |
| identity (no record_data) | 0.253s |   39,528 | 0.253s | 0.244s | 0.259s |
| snapshot no masks         | 0.258s |   38,779 | 0.260s | 0.245s | 0.282s |
| snapshot 1 mask (email)   | 0.291s |   34,422 | 0.299s | 0.275s | 0.346s |
| snapshot 3 masks          | 0.352s |   28,406 | 0.351s | 0.340s | 0.359s |

## Dashboard Queries

- Deletions seeded: 1,000,000
- Table events seeded: 5,000
- Audit indexes: default install set (record/actor/deleted_at/table_name + record-lookup)
- Each query is run twice; the EXPLAIN (ANALYZE, BUFFERS) timing reported is the warm-cache run

| Scenario                              | Median |
| ------------------------------------- | -----: |
| `FeedQuery#page` no filter (30d)      |  87 ms |
| `FeedQuery#page` model=Comment        |  59 ms |
| `FeedQuery#page` time=24h             |  18 ms |
| `FeedQuery#page` time=all             | 144 ms |
| `FeedQuery#page` actor=user:User:42   |  45 ms |
| `FeedQuery#page` actor=anon           |  54 ms |
| `FeedQuery#page` actor=sys:retention_job |  70 ms |
| `FeedQuery#page` q=req_a (search)     | 528 ms |
| `FeedQuery#page` page=100             | 101 ms |
| `FeedQuery#total` no filter           |  43 ms |
| `FeedQuery#total` model=Comment       |  44 ms |
| `KpiCalculator` no model              | 399 ms |
| `KpiCalculator` model=Comment         | 180 ms |
| `Sparkline` no model                  |  54 ms |
| `Sparkline` model=Comment             |  67 ms |
| `ActorOptions` users                  |  46 ms |
| `ActorOptions` system                 |  29 ms |

Adding two extra btree indexes — `(record_type, deleted_at DESC)` and `(actor_type, actor_id, deleted_at DESC)` — cuts model-scoped and actor-scoped queries by 50–70% (KPI model=Comment 180→125 ms, ActorOptions users 46→40 ms, Sparkline model=Comment 67→24 ms, FeedQuery#total model=Comment 44→19 ms). They are not part of the default install: every additional index also slows audit *capture* on every host DELETE, and the default numbers are already sub-second per query at 1M rows. Add them yourself if your audit tables are large enough that dashboard latency outweighs the capture-path overhead.

## Reading Results

- `no trigger` is PostgreSQL's plain bulk delete baseline.
- SQL-level `disabled trigger` uses session-level `SET athar.disabled = 'on'`; it measures trigger-dispatch and `WHEN`-clause overhead, not Ruby `Athar.without_capture` overhead.
- `identity capture` measures one audit insert per deleted row with empty `record_data`.
- `identity + metadata` adds the cost of reading and storing `athar.meta`.
- `only capture` measures filtered JSONB capture for selected columns.
- `snapshot capture` measures full-row JSONB capture.
- Rails `delete_all` behaves like the SQL bulk benchmark because it sends one bulk `DELETE`.
- Rails `destroy_all` is dominated by Active Record object loading and per-record destroy work, so Athar is a smaller relative part of the total.
- Rails bulk `without_capture` scenarios run each measured action inside a matching outer transaction so they do not get a hidden transaction advantage from `Athar.without_capture`.
- Single-record `without_capture/call` scenarios call `Athar.without_capture` once per individual operation, so those rows include per-call context overhead as well as trigger bypass behavior.
- Single-record Rails deletes are dominated by Active Record and round-trip overhead. The benchmark creates records outside the timed section, then reports median delete time across repeated runs.
- Data-masking scenarios all use `snapshot` capture against the same 10,000-row seed, so the only variable is the number and type of mask functions invoked per row. The `identity` row is included as a no-record_data baseline against which `snapshot no masks` measures the cost of capturing the full row without any masking.
- Dashboard queries are measured against a synthetic 1M-row dataset with realistic distribution (mixed record types, actors, and a recency-skewed time spread). Times are warm-cache; the first cold query is typically 2–3× slower. Search performance (`q=…`) is dominated by `ILIKE` over text + JSONB columns and is the primary candidate for `pg_trgm` indexing on very large tables.

Use the median as the headline number. The mean, min, and max are there to show local noise. Identity capture should be the recommended mode for high-churn tables; prefer `--only` to `--snapshot` when you must retain row attributes.
