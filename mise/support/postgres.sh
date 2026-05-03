#!/usr/bin/env bash

set -euo pipefail

COMPOSE_FILE="${ATHAR_COMPOSE_FILE:-dev-docker-compose.yml}"
export ATHAR_DB_HOST="${ATHAR_DB_HOST:-localhost}"
export ATHAR_DB_PORT="${ATHAR_DB_PORT:-5434}"
export ATHAR_DB_USER="${ATHAR_DB_USER:-athar}"
export ATHAR_DB_PASSWORD="${ATHAR_DB_PASSWORD:-athar}"

docker_start() {
  docker compose -f "$COMPOSE_FILE" up -d
  wait_for_postgres
  wait_for_host_port
}

docker_stop() {
  docker compose -f "$COMPOSE_FILE" down
}

with_postgres() {
  if compose_postgres_running; then
    docker_start
    return
  fi

  trap docker_stop EXIT
  docker_start
}

wait_for_postgres() {
  for _ in {1..30}; do
    if docker compose -f "$COMPOSE_FILE" exec -T postgres \
      pg_isready -U "$ATHAR_DB_USER" -d postgres >/dev/null 2>&1; then
      return 0
    fi

    sleep 1
  done

  docker compose -f "$COMPOSE_FILE" logs postgres
  echo "PostgreSQL did not become ready in time" >&2
  return 1
}

wait_for_host_port() {
  for _ in {1..30}; do
    if nc -z "$ATHAR_DB_HOST" "$ATHAR_DB_PORT" >/dev/null 2>&1; then
      return 0
    fi

    sleep 1
  done

  echo "PostgreSQL host port $ATHAR_DB_HOST:$ATHAR_DB_PORT did not become reachable in time" >&2
  return 1
}

compose_postgres_running() {
  local container_id
  container_id="$(docker compose -f "$COMPOSE_FILE" ps -q postgres 2>/dev/null || true)"
  [ -n "$container_id" ] &&
    [ "$(docker inspect -f "{{.State.Running}}" "$container_id" 2>/dev/null || true)" = "true" ]
}

ensure_database() {
  local database="$1"

  case "$database" in
    ""|*[!a-zA-Z0-9_]*)
      echo "Unsafe database name: $database" >&2
      return 1
      ;;
  esac

  if docker compose -f "$COMPOSE_FILE" exec -T postgres psql \
    -U "$ATHAR_DB_USER" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '$database'" |
    grep -qx "1"; then
    return 0
  fi

  docker compose -f "$COMPOSE_FILE" exec -T postgres createdb -U "$ATHAR_DB_USER" "$database"
}
