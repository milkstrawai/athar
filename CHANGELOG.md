# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and this project adheres to Semantic Versioning.

## [0.3.0] - 2026-05-10

### Added

- Read-only deletion-audit dashboard mounted at the engine root. Renders sidebar of tracked models, KPI strip, filter bar, paginated unified feed of `athar_deletions` and `athar_table_events`, and expandable detail. Tracked models are discovered at runtime from `pg_trigger`; no registry table. Self-contained CSS and JS under `app/assets/`, served through the host's asset pipeline (Sprockets or Propshaft) when available or by a built-in `Rack::Static` middleware otherwise; no `turbo-rails`, `stimulus-rails`, or `importmap-rails` required. Document the mount pattern and route-constraint auth in the README.

## [0.2.1] - 2026-05-06

### Fixed

- Fixed `athar:install --update` migrations to replace SQL functions without dropping them, avoiding PostgreSQL dependency errors when existing triggers depend on `athar_capture_delete()`.

## [0.2.0] - 2026-05-05

### Added

- Data masking for `athar_deletions.record_data`.
  - Built-in masks: `:email`, `:partial:N:M`, `:hash`.
  - New `athar:mask` generator for named regex masks.
  - Custom mask functions via `athar_mask_<name>(jsonb) RETURNS jsonb`.
  - New `--mask=col:mask_name[:arg...]` flag on `athar:model`.
- Bumped `athar_capture_delete` to v02 (adds optional 9th trigger argument for masks).

### Upgrade

After bundling, run:

```sh
bin/rails generate athar:install --update
bin/rails db:migrate
```

This installs the new built-in mask functions and bumps `athar_capture_delete`. Existing model triggers continue to work without regeneration; regenerate them only if you want to add masks (`bin/rails generate athar:model X --update --mask=...`).

## [0.1.0] - 2026-05-03

### Added

- Initial release of Athar, a Rails gem for PostgreSQL trigger-based deletion auditing without soft delete.
- `athar:install` generator for shared `athar_deletions` and `athar_table_events` audit tables.
- `athar:model` generator for installing, updating, and removing per-table delete triggers.
- Fx-backed migrations by default, with raw SQL migration support through `--no-fx`.
- Identity-only, selected-column (`--only`), and full-row (`--snapshot`) delete capture modes.
- STI-aware deleted-record type capture through `--record-type-column`.
- Schema-qualified table support, including automatic schema inference from model table names.
- Optional `--track-truncate` support for statement-level `TRUNCATE` events.
- Runtime context APIs: `Athar.with_actor`, `Athar.with_metadata`, `Athar.with_context`, and `Athar.without_capture`.
- `Athar::Deletion` and `Athar::TableEvent` read models for querying audit records.
- Actor lookup helpers for Active Record actors stored in `actor_type` and `actor_id`.
- Retention configuration, `Athar::Retention`, and `Athar::RetentionJob` for age and count pruning.
- Support for bigint and UUID audit schemas, with documented behavior for mixed-id applications.
- Local Docker Compose PostgreSQL setup for development and tests.
- Mise tasks for running tests, Docker helpers, and local benchmarks.
- SQL-level, Rails bulk-delete, and Rails single-record benchmark scripts with recorded baseline results.
- CI coverage across supported Rails versions, Ruby versions, Fx/no-Fx modes, and PostgreSQL 13/18.
