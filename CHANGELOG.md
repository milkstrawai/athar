# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and this project adheres to Semantic Versioning.

## [Unreleased]

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
