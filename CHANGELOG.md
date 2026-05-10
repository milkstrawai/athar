# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and this project adheres to Semantic Versioning.

## [0.3.4] - 2026-05-10

### Fixed

- Fixed the dashboard's filter bar (Time / Mode / Kind segments) showing the previously-selected segment as active after a click. The filter bar lives outside the partial-swap regions so the search input keeps its focus across navigations; its highlight is reconciled from `window.location.href` after each swap. That reconciliation ran before `history.pushState` updated the URL, so it always read one navigation behind. Pushing state first lets the reconciliation see the URL the user just navigated to.

## [0.3.3] - 2026-05-10

### Fixed

- Fixed `PG::DatatypeMismatch: UNION types <pk_type> and bigint cannot be matched` when opening the dashboard on hosts where `Rails.configuration.generators.options[:active_record][:primary_key_type] = :uuid` (or `:integer`) caused the install migration to create the audit tables with a non-bigint primary key. The dashboard's UNION between `athar_deletions` and `athar_table_events` now resolves the audit `id` SQL type at runtime and types the empty UNION leg accordingly, so it composes cleanly regardless of the host's primary-key choice.

### Added

- `Athar.audit_connection` and `Athar.audit_db_config` module methods centralizing the connection both audit tables share. Multi-database hosts can route audit storage to a dedicated connection by calling `Athar::Deletion.connects_to(...)` in an initializer; the dashboard, retention, and generators follow automatically. The dashboard topbar now reflects the audit DB name when this routing is configured.
- `FeedQuery` raises `ArgumentError` up-front when `athar_deletions.id` and `athar_table_events.id` resolve to different SQL types, replacing a cryptic Postgres UNION error with a clear message naming both tables and their detected types.

## [0.3.2] - 2026-05-10

### Fixed

- Logo and favicon now resolve via the engine's own asset helper, which falls back to the bundled `Athar::Middleware::AssetServer` when the host's asset pipeline cannot locate `athar/logo.png`. The 0.3.1 fix relied on host-pipeline auto-discovery and still failed on hosts using `vite_ruby` or non-default Propshaft configurations. The middleware now also serves `.png` and `.svg` files from `app/assets/images/athar/`.

## [0.3.1] - 2026-05-10

### Fixed

- Fixed `Propshaft::MissingAssetError` for `athar/logo.png` on hosts with a non-default asset pipeline. The engine now explicitly registers `app/assets/images` on `app.config.assets.paths` (alongside `stylesheets` and `javascripts`) and lists the logo in `assets.precompile` for Sprockets-based hosts. Auto-discovery of engine `app/assets/*` paths cannot be relied on across all host setups (e.g. apps using `vite_ruby` or custom Sprockets configuration).

## [0.3.0] - 2026-05-10

### Added

- Read-only deletion-audit dashboard mounted at the engine root. Renders sidebar of tracked models, KPI strip, filter bar, paginated unified feed of `athar_deletions` and `athar_table_events`, and expandable detail. Tracked models are discovered at runtime from `pg_trigger`; no registry table. Self-contained CSS and JS under `app/assets/`, served through the host's asset pipeline (Sprockets or Propshaft) when available or by a built-in `Rack::Static` middleware otherwise; no `turbo-rails`, `stimulus-rails`, or `importmap-rails` required. Document the mount pattern and route-constraint auth in the README.

### Fixed

- `athar:model --remove` no longer crashes with `NameError` when the model class no longer exists.
- `MetadataStack.clear!` is now called automatically after every Rails request via `Athar::MetadataStackMiddleware`, preventing metadata stack leaks between requests.
- `split_schema_qualified` now uses the configured `default_schema` instead of hardcoding `"public"`.
- Disambiguated the `record_type_column` sentinel value: changed from `'null'` to `'__athar_none__'` so a column literally named `"null"` is no longer treated as absent.

### Changed

- Replaced all `Thor::Error` raises in generators with `Athar::GeneratorError < Athar::Error` for a consistent error taxonomy.
- SQL identifiers in retention queries are now properly quoted via `quote_table_name` and `quote_column_name`.
- `Retention.prune_by_count` now accepts `time_column:` and `primary_key:` keyword arguments (defaults `"deleted_at"` and `"id"`) for generic table support.
- `Retention.prune!` refactored into smaller focused methods; all RuboCop metric disables removed.
- `VERSION` constant is now explicitly frozen.

### Performance

- `MetadataStack.current` optimized from O(n²) to O(1) via a cached merge that invalidates on `pop`/`clear!`.
- `ActorLookup#actor` is now memoized per-instance; added `ActorLookup.for_records` for batch actor pre-loading.
- `Deletion.for_record` caches `constantize` lookups in a thread-safe `Mutex`-guarded cache.
- SQL trigger `athar_capture_delete` now skips `to_jsonb(OLD)` in identity mode, extracting only the primary key (and STI column if needed) directly.

### Security

- Context `SET_LOCAL` restore in `with_metadata` and `without_capture` ensure blocks is now guarded with `connection.transaction_open?`, preventing errors when the transaction has already rolled back.

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
