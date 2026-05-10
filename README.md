<p align="center">
  <img src="docs/logo.png" alt="Athar logo" width="160">
</p>

<h1 align="center">Athar</h1>

<p align="center">
  <a href="https://badge.fury.io/rb/athar"><img src="https://badge.fury.io/rb/athar.svg" alt="Gem Version"></a>
  <a href="https://github.com/milkstrawai/athar/actions"><img src="https://github.com/milkstrawai/athar/actions/workflows/ci.yml/badge.svg" alt="Build Status"></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License: MIT"></a>
  <a href="https://www.ruby-lang.org"><img src="https://img.shields.io/badge/ruby-%3E%3D%203.2-blue" alt="Ruby >= 3.2"></a>
  <a href="https://rubyonrails.org"><img src="https://img.shields.io/badge/rails-%3E%3D%207.2-red" alt="Rails >= 7.2"></a>
  <a href="https://www.postgresql.org"><img src="https://img.shields.io/badge/postgresql-%3E%3D%2013-336791" alt="PostgreSQL >= 13"></a>
</p>

<p align="center">
  <strong>Database-level deletion auditing for Rails applications without soft delete.</strong>
</p>

Athar (Arabic: أَثَر, "trace"; pronounced **A-thar**) records physical database deletions in Rails applications. Instead of leaving deleted rows in their original tables behind a `deleted_at` filter, Athar lets the row be removed and writes a separate audit row to `athar_deletions` using PostgreSQL triggers.

Athar answers one question:

> What was deleted, when was it deleted, and who or what caused the deletion?

It does not turn deleted rows into queryable models, and it does not provide full record version history.

## Table of Contents

- [The Problem](#the-problem)
- [The Solution](#the-solution)
- [Requirements](#requirements)
- [Installation](#installation)
- [Upgrading](#upgrading)
- [Quick Start](#quick-start)
- [Usage](#usage)
- [Configuration](#configuration)
- [How It Works](#how-it-works)
- [Operational Notes](#operational-notes)
- [Dashboard](#dashboard)
- [Troubleshooting](#troubleshooting)
- [Development](#development)
- [Contributing](#contributing)
- [License](#license)

## The Problem

Soft delete keeps deleted rows in the original table. That usually means `default_scope` filters, relaxed unique indexes, conditional foreign-key behavior, and query bugs when deleted rows accidentally leak into normal application reads.

It also changes what "delete" means. The application says a row is gone, but the database still has it. Over time, teams end up designing around the soft-delete column instead of using the database's normal integrity model.

## The Solution

Athar keeps deletion semantics simple: rows are physically deleted from their original tables, and PostgreSQL triggers write audit records into separate tables.

This gives you:

- Normal database deletes and constraints.
- Audit rows outside the original table.
- Capture for deletes from Active Record, raw SQL, cascades, and bulk deletes.
- A narrow audit model focused on deletions, not full version history.

## Requirements

- Ruby 3.2+
- Rails 7.2+
- PostgreSQL 13+

Athar supports apps configured with bigint or UUID primary keys. In apps with mixed primary key types, Athar supports tracking tables whose primary key type matches the shared audit table ID type. Tables using a different primary key type are not supported by the default audit schema.

## Installation

Add Athar to your Gemfile:

```ruby
gem "athar"
```

Install and run the generator:

```sh
bundle install
bin/rails generate athar:install
bin/rails db:migrate
```

This creates the shared audit tables (`athar_deletions`, `athar_table_events`) and installs Athar's PostgreSQL functions.

By default, Athar uses the [`fx`][fx] gem so PostgreSQL functions and triggers can round-trip through `db/schema.rb`. If you cannot or do not want to use Fx, pass `--no-fx`; that path requires:

```ruby
# config/application.rb
config.active_record.schema_format = :sql
```

The generators raise a clear error if you pass `--no-fx` while the host app still uses `schema.rb`. They never edit `config/application.rb` for you.

## Upgrading

After upgrading Athar, run the install generator in update mode and migrate:

```sh
bin/rails generate athar:install --update
bin/rails db:migrate
```

This updates Athar's shared PostgreSQL functions without recreating the audit tables. Existing model triggers continue to work; regenerate a model trigger only when you want to change its capture policy, for example to add masks:

```sh
bin/rails generate athar:model User --update --snapshot --mask=email:email
bin/rails db:migrate
```

## Quick Start

Install capture for a model:

```sh
bin/rails generate athar:model User --only=email,name,account_id
bin/rails db:migrate
```

Delete a record:

```ruby
Athar.with_actor(current_user) do
  User.find(user_id).destroy!
end
```

Query the audit row:

```ruby
deletion = Athar::Deletion.for_record(User, user_id).last
deletion.record_type # => "User"
deletion.record_id   # => user_id
deletion.actor       # => current_user
deletion.record_data # => { "email" => "...", "name" => "...", "account_id" => ... }
```

The `users` row is gone. The audit row remains in `athar_deletions`.

## Usage

### Capture Per Model

Triggers are installed per table:

```sh
bin/rails generate athar:model User --only=email,name,account_id
bin/rails db:migrate
```

Then deletes via any path are captured:

```ruby
User.find(user_id).destroy!                 # captured
User.where(spam: true).delete_all           # captured, one audit row per deleted row
ActiveRecord::Base.connection.execute(...)  # captured
```

The model file does not change. Capture policy is owned by the trigger. To change an existing trigger, run `generate athar:model` with `--update` and the new options.

### Capture Modes

| Mode             | CLI                                       | What is stored in `record_data` |
| ---------------- | ----------------------------------------- | -------------------------------- |
| Identity-only    | `bin/rails g athar:model User`            | `{}` (default)                   |
| Selected columns | `bin/rails g athar:model User --only=...` | Only listed columns              |
| Full snapshot    | `bin/rails g athar:model User --snapshot` | All row attributes including `id` |

Identity-only is the default and is recommended for high-churn tables. Prefer `--only` for PII-sensitive records over `--snapshot`. `--except` is not supported because it is too easy to accidentally retain new sensitive columns.

### Data Masking

Athar can mask values inside `record_data` before they are stored, so the audit log keeps signal without retaining the original sensitive value:

```sh
bin/rails generate athar:model User --snapshot --mask=email:email,phone:partial:0:4
bin/rails db:migrate
```

```ruby
User.find(user_id).destroy!
Athar::Deletion.last.record_data
# => { "email" => "use***@example.com", "phone" => "********4567", ... }
```

Three built-in masks are available:

| Spec | Behavior | Example |
|------|----------|---------|
| `email` | Keeps the first 3 chars of the local part, then `***@<domain>`. | `user.name@example.com` → `use***@example.com` |
| `partial:N:M` | Keeps the first `N` and last `M` characters; replaces the middle with `*` (length-preserving). When `N + M ≥ length`, returns all asterisks. | `4111111111111111` with `partial:0:4` → `************1111` |
| `hash` | Plain SHA-256 hex of the textual form. Deterministic across rows. | `user.name@example.com` → 64 hex chars |

Mask spec format: `column:mask_name[:arg1:arg2]`. Multiple specs are comma-separated. Built-ins each have a fixed arity (`partial` takes two integer args; `email` and `hash` take none). Custom mask functions take no DSL args.

The `--mask` flag requires `--only` or `--snapshot`; identity-only capture has nothing to mask.

#### Named Regex Masks

For per-app patterns where the built-ins do not fit, install a named regex mask:

```sh
bin/rails generate athar:mask ssn_keep_last4 \
  --regex='^([0-9]{3})-([0-9]{2})-([0-9]{4})$' \
  --replacement='XXX-XX-\3'
bin/rails db:migrate
```

Reference it from a model:

```sh
bin/rails generate athar:model User --snapshot --mask=ssn:ssn_keep_last4
bin/rails db:migrate
```

`bin/rails generate athar:mask <name> --update --regex=... --replacement=...` regenerates the function. `--remove` drops it (and refuses if any model trigger still references it).

#### Custom Mask Functions

Applications can install any PostgreSQL function with the signature `athar_mask_<name>(value jsonb) RETURNS jsonb` and reference it from `--mask`:

```sql
CREATE OR REPLACE FUNCTION athar_mask_uae_phone(value jsonb) RETURNS jsonb AS $$
DECLARE text_value text;
BEGIN
  IF value IS NULL OR jsonb_typeof(value) <> 'string' THEN RETURN value; END IF;
  text_value := value #>> '{}';
  RETURN to_jsonb(regexp_replace(text_value, '^\+971([0-9]{2})[0-9]+([0-9]{4})$', '+971\1****\2'));
END;
$$ LANGUAGE plpgsql IMMUTABLE;
```

```sh
bin/rails generate athar:model User --snapshot --mask=phone:uae_phone
```

The names `email`, `partial`, and `hash` are reserved and cannot be used by custom or named-regex masks.

#### Privacy and Operational Notes

> [!IMPORTANT]
> Masking only protects what is stored in `athar_deletions`. It does **not** redact values from the PostgreSQL WAL — logical replication, point-in-time recovery, and `pg_dump` see the original `DELETE` row before the trigger fires.

- `:hash` is unsalted SHA-256. Same input always yields the same digest, which lets analysts correlate deletions across tables but means the audit log is brute-forceable for small input universes (emails, phone numbers, national IDs).
- Identity columns (`record_id`, `record_type`, `actor_*`, `schema_name`, `table_name`, `deleted_at`) are never masked; they are indexed lookup keys.
- Mask spec is frozen into the trigger at migration time. There is no runtime override.

### Generator Options

- `--primary-key=id`
- `--record-type=User` (override stored `record_type` for non-STI models)
- `--record-type-column=type` (STI inheritance column; pass `false` to disable)
- `--schema=reporting` (override schema; inferred from schema-qualified model table names, otherwise `public`)
- `--track-truncate` (also install a statement-level `AFTER TRUNCATE` trigger)
- `--update` (drop and recreate the trigger with new arguments)
- `--remove` (drop the trigger)
- `--fx` / `--no-fx` (force Fx-backed or raw-SQL migrations; default is Fx when available)

> [!WARNING]
> `--update` and `--remove` migrations are intentionally irreversible by default. Athar cannot reconstruct the previous trigger arguments after the fact. Keep your old migrations as the source of truth for the previous state.

### Actor And Metadata

Wrap delete code to attach actor and request/job context:

```ruby
Athar.with_actor(current_user) do
  user.destroy!
end

Athar.with_metadata(ip: request.remote_ip, request_id: request.request_id) do
  user.destroy!
end

Athar.with_context(actor: current_user, reason: "GDPR request") do
  user.destroy!
end
```

These methods write JSON into a transaction-scoped PostgreSQL setting that the trigger reads.

`Athar.with_actor` only accepts an `ActiveRecord::Base` instance. Symbolic actors must go in metadata:

```ruby
Athar.with_metadata(actor: "cron", reason: "retention cleanup") do
  User.where(inactive: true).delete_all
end
```

For STI actors, Athar stores the actor's base class in `actor_type` for stable lookup. Deleted records still store the concrete STI class in `record_type`.

If raw `athar.meta` JSON contains an `actor_id` value that cannot be cast to the configured id type (for example, `"cron"` in a bigint app), the trigger raises and the delete fails. Athar prefers a loud error over silently saving an invalid audit row.

### Disabling Capture

```ruby
Athar.without_capture do
  Session.where("expires_at < ?", 1.month.ago).delete_all
end
```

Internally this issues `SET LOCAL athar.disabled TO 'on'` for the current transaction. The trigger's `WHEN` clause skips the function body while disabled.

### Querying The Audit Log

```ruby
Athar::Deletion.for_record(User, user_id)
Athar::Deletion.for_record_type("Admin")
Athar::Deletion.for_table("users")
Athar::Deletion.by_actor(current_user)
Athar::Deletion.recent
Athar::Deletion.before(1.week.ago)
Athar::Deletion.after(Date.today)

deletion = Athar::Deletion.last
deletion.record_data
deletion.metadata
deletion.actor
```

Athar does not define `belongs_to :record`. The deleted row is gone, so the audit row is the source of truth.

### TRUNCATE Events

`TRUNCATE` does not fire row-level `DELETE` triggers. If you need to know when a table was truncated, opt in:

```sh
bin/rails generate athar:model User --track-truncate
```

This installs a statement-level `AFTER TRUNCATE` trigger that writes one row to `athar_table_events`. The truncated row contents are not preserved because PostgreSQL does not expose them to statement-level triggers.

## Configuration

Athar can be configured from an initializer:

```ruby
Athar.configure do |config|
  config.retention.max_age = 1.year
  config.retention.max_count = 1_000_000
  config.retention.batch_size = 1_000
  config.retention.max_batches_per_run = 100
  config.retention.queue_name = :athar
end
```

Then schedule the retention job with your job scheduler:

```ruby
Athar::RetentionJob.perform_later
```

The job runs `Athar::Retention.prune!`, which:

1. Deletes audit rows older than `max_age` in batches.
2. Deletes rows beyond `max_count` (oldest first) in batches, after age pruning.
3. Stops at `max_batches_per_run` so a first cleanup on a huge audit table cannot monopolize a worker. The next scheduled run continues.

By default, age pruning also covers `athar_table_events`. Disable with `config.retention.prune_table_events = false`.

## How It Works

### Schema Dump Strategy

Athar relies on PostgreSQL functions and triggers. By default it uses [`fx`][fx] as a runtime dependency so your host app can keep using `db/schema.rb`:

- Functions land in `db/functions/<name>_v01.sql`.
- Triggers land in `db/triggers/<name>_v01.sql`.
- Migrations call `create_function`, `create_trigger`, `update_function`, `update_trigger`, and `drop_trigger`.
- Subsequent `--update` runs write `_v02.sql`, `_v03.sql`, etc., and emit `update_function` / `update_trigger` migrations.
- [`fx`][fx]'s schema dumper preserves them in `schema.rb` so Rails' default `bin/rails db:schema:load` round-trips correctly.

With `--no-fx`, Athar writes raw SQL migrations. Raw SQL migrations require `config.active_record.schema_format = :sql`.

### Delete Capture Flow

Each tracked table gets a `BEFORE DELETE` trigger. When PostgreSQL deletes a row, the trigger:

1. Reads the old row.
2. Computes `record_type` and `record_id`.
3. Builds `record_data` based on the capture mode.
4. Reads actor and metadata from `athar.meta`.
5. Inserts one row into `athar_deletions`.

Because the trigger runs in PostgreSQL, Athar captures deletes from Active Record callbacks, `delete_all`, raw SQL, and database cascades as long as the deleted table has an Athar trigger installed.

### STI

Athar reads the inheritance column at delete time. If the row's `type` is populated (for example `Admin < User`), `record_type` becomes `"Admin"`. The default inheritance column is auto-detected from the model. Override with `--record-type-column=mycolumn` or disable with `--record-type-column=false`.

### Prior Art

| Tool                           | Focus                                                                                                    | Capture mechanism       |
| ------------------------------ | -------------------------------------------------------------------------------------------------------- | ----------------------- |
| [Logidze][logidze]             | Record versioning; history lives on the original row, so hard-deleted rows are not Athar deletion records | PostgreSQL triggers     |
| [paper_trail][paper_trail]     | Record versioning                                                                                        | Active Record callbacks |
| [discard][discard], [paranoia] | Soft delete                                                                                              | Default scope filters   |
| [pg_audit_log][pg_audit_log]   | Trigger-based audit log; no longer maintained for modern Rails                                           | PostgreSQL triggers     |

Athar focuses narrowly on deletion capture. It borrows the database-trigger/generator approach from tools like Logidze, but stores hard-delete records separately instead of keeping version history on the original row.

## Operational Notes

### Privacy

Athar stores data that the application deleted. That creates obligations.

- Default to identity-only capture.
- Prefer `--only` over `--snapshot`. New sensitive columns added later will not silently leak into the audit log.
- Treat `record_data` and `metadata` as PII unless you have audited them.
- Configure retention from day one in production.

### Performance

Every captured row deletion adds:

1. The original delete.
2. One insert into `athar_deletions`.
3. JSONB serialization of `record_data`.
4. Index writes on the audit row.

For high-churn tables (sessions, transient tokens, event buffers, job internals), either skip Athar entirely, use identity-only capture, or wrap operational cleanup in `Athar.without_capture`.

### Audit-Table Query Patterns

Athar creates indexes for common lookup paths:

- `(record_type, record_id)` for `Athar::Deletion.for_record(User, id)`
- `(actor_type, actor_id)` for `Athar::Deletion.by_actor(user)`
- `(deleted_at, id)` for retention and time-window queries
- `(table_name, deleted_at)` for table-scoped time-window queries
- `(schema_name, table_name, record_id)` for schema/table/id lookups
- `athar_table_events.occurred_at` for table-event retention

These indexes are aimed at specific audit lookups, not every possible reporting query. If your application frequently filters by a broad field such as `record_type` alone, `table_name` alone, actor type alone, or keys inside `record_data` / `metadata`, add application-specific indexes based on your real query patterns.

For large audit tables, prefer queries that include a selective id or time window, such as `for_record(User, id)` or `for_table("users").after(30.days.ago)`.

### Cascading Deletes

Athar captures deletes only for tables that have an Athar trigger installed. That includes:

- `dependent: :destroy` cascades, where Rails iterates and Athar's trigger fires per row.
- `dependent: :delete_all` cascades.
- Database `ON DELETE CASCADE` cascades, where PostgreSQL fires the child triggers.

If a child table has no Athar trigger, deletes on it are not captured even when the parent does.

### Benchmarks

There are local benchmark tasks for measuring SQL-level and Rails-level delete overhead:

```sh
mise run bench:delete_capture
mise run bench:rails_bulk
mise run bench:rails_single
```

The tasks start the local `postgres:18` Docker Compose service when needed, create the throwaway benchmark database, run the benchmark, and stop only the service they started.

Results are machine-dependent. The scripts are intentionally not part of CI; they exist so maintainers can spot large regressions. See [`bench/RESULTS.md`](bench/RESULTS.md) for the last measured baseline.

## Dashboard

Athar ships a read-only audit dashboard as a Rails engine. It provides a browser interface for the data that Athar's triggers write to `athar_deletions` and `athar_table_events`.

![Athar dashboard](docs/screenshots/dashboard.png)

### Mounting

Add the engine to your host app's `config/routes.rb`:

```ruby
mount Athar::Engine => "/athar"
```

### Authentication

The engine has no built-in authentication and inherits from the host's `::ApplicationController`, so any `before_action`-based auth (session checks, policy gates) carries through automatically.

For Devise-protected apps, wrap the mount in a route constraint:

```ruby
authenticate :user, ->(u) { u.admin? } do
  mount Athar::Engine => "/athar"
end
```

Any controller-level authentication strategy that works for your host app works here.

### Dependencies

Athar's only runtime dependencies are `activejob`, `activerecord`, `activesupport`, `railties`, and `fx`. The dashboard ships its own CSS and JS files, so `turbo-rails`, `stimulus-rails`, and `importmap-rails` are not required. The host's asset pipeline (Sprockets or Propshaft) serves those files when one is available; otherwise they're served by a `Rack::Static`-backed middleware bundled with the gem. Hosts that already use Hotwire are unaffected: the engine has its own layout, and dashboard pages set `<meta name="turbo-visit-control" content="reload">` so any Turbo Drive in the host falls back to a full page load when entering `/athar`.

### What the dashboard shows

- **Sidebar** — tracked models grouped by schema, with capture mode, masks, STI flag, truncate flag, and per-model audit row count. Discovered at runtime from `pg_trigger`; no registry table.
- **KPI strip** — filtered row count, last 24 h, last 7 d with vs-prior delta, truncate event count, distinct actor count, and a 14-day sparkline.
- **Filter bar** — full-text search across record/actor/metadata/data; time, mode, and kind segments; actor dropdown; clear.
- **Unified feed** — paginated list of `athar_deletions` and truncate events from `athar_table_events`. Each row expands inline to show `record_data`, metadata, identity fields, and a requery snippet in both Ruby and SQL.
- **Permalinks** — individual deletion at `/athar/deletions/:id`; individual table event at `/athar/table_events/:id`.

### What it does not do

The dashboard is read-only. There is no retention or configuration UI, no manual actions, no export, and no live updates (no polling, no Turbo Streams).

### Privacy

`record_data` is rendered as stored. Masking happens at trigger time, not at render time. The dashboard inherits whatever masking the host configured when the trigger was installed.

> [!IMPORTANT]
> If a trigger was installed without masking, the dashboard renders the raw values. Mask at the trigger level before sensitive data is written to `athar_deletions`.

### Performance

The index renders approximately 8–10 queries. Sidebar model counts and the actor dropdown query scale with audit-table size. Search uses `ILIKE` scans bounded by the active time filter. For very large audit tables, prefer narrower time windows when searching.

## Troubleshooting

### "Function `athar_capture_delete` does not exist"

Run the install generator and migrate:

```sh
bin/rails generate athar:install
bin/rails db:migrate
```

### "PG::DatatypeMismatch: column `record_id` is of type bigint but expression is of type uuid"

You generated a trigger for a table whose primary key type does not match the shared audit table ID type. Track tables with the matching ID type, or customize the audit schema.

### "Audit row missing for `delete_all`"

Confirm the table has an Athar trigger installed, and confirm the delete was not wrapped in `Athar.without_capture`.

### "Function `athar_mask_foo` does not exist"

The function was dropped after the trigger was installed (or `bin/rails generate athar:install --update` was never run after upgrading the gem). Either reinstall the function, run `--update`, or run `bin/rails generate athar:model X --update` to regenerate the trigger without the orphan reference.

### "athar_mask_partial: head and tail must be non-negative"

A trigger was hand-edited or constructed with negative `partial` arguments. The generator validates this at scaffold time, so the runtime check only fires for triggers that bypassed the generator.

## Development

The maintained local workflow is mise:

```sh
mise run test
```

The test task installs missing gems for the pinned Ruby, starts PostgreSQL 18 when needed, creates the needed test databases, and runs both the Fx-backed and raw-SQL test suites. The raw commands are still ordinary Bundler/Rake commands if you do not use mise.

The dummy app under `test/dummy` is a real Rails app. By default it uses `schema.rb` + Fx; `ATHAR_NO_FX=1` flips it to `structure.sql` and the raw-SQL generator path. Tests use real triggers against a real database in both modes.

### Dashboard assets

The dashboard's CSS and JS are in `app/assets/stylesheets/athar/dashboard.css` and `app/assets/javascripts/athar/dashboard.js`. There's no build step: edit the file and reload the browser. The JS is a single IIFE that handles every dashboard interaction via delegated event listeners on `document`, including the partial-fetch swaps that keep `#athar-dashboard` in sync with the URL. `Athar::Middleware::AssetServer` serves the files at `/athar-assets/<gem-version>/dashboard.{js,css}` for hosts without an asset pipeline; everyone else gets digested URLs from Sprockets or Propshaft.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/milkstrawai/athar.

When contributing, include tests for behavior changes, keep generated SQL/migration behavior explicit, and update documentation when user-facing behavior changes.

## License

Athar is available as open source under the terms of the [MIT License](LICENSE.txt).

[logidze]: https://github.com/palkan/logidze
[paper_trail]: https://github.com/paper-trail-gem/paper_trail
[discard]: https://github.com/jhawthorn/discard
[paranoia]: https://github.com/rubysherpas/paranoia
[pg_audit_log]: https://github.com/Casecommons/pg_audit_log
[fx]: https://github.com/teoljungberg/fx
