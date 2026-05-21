#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
postgres_container=""
mysql_container=""

cleanup() {
  if [[ -n "$postgres_container" ]]; then
    docker rm -f "$postgres_container" >/dev/null 2>&1 || true
  fi
  if [[ -n "$mysql_container" ]]; then
    docker rm -f "$mysql_container" >/dev/null 2>&1 || true
  fi
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

wait_for_container() {
  local container="$1"
  local command="$2"
  for _ in $(seq 1 80); do
    if docker exec "$container" sh -lc "$command" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.5
  done

  echo "Container $container did not become ready" >&2
  docker logs "$container" >&2 || true
  return 1
}

start_postgres() {
  postgres_container="ledger-postgres-test-$$"
  docker run --rm -d \
    --name "$postgres_container" \
    -e POSTGRES_USER=ledger \
    -e POSTGRES_PASSWORD=ledger \
    -e POSTGRES_DB=ledger_test \
    -p 127.0.0.1::5432 \
    postgres:16-alpine >/dev/null

  wait_for_container "$postgres_container" "pg_isready -U ledger -d ledger_test"
  local port
  port="$(docker port "$postgres_container" 5432/tcp | sed -E 's/.*:([0-9]+)$/\1/')"
  LEDGER_TEST_POSTGRES_DSN="postgres://ledger:ledger@127.0.0.1:${port}/ledger_test?sslmode=disable&TimeZone=UTC"
  export LEDGER_TEST_POSTGRES_DSN
}

start_mysql() {
  mysql_container="ledger-mysql-test-$$"
  docker run --rm -d \
    --name "$mysql_container" \
    -e MYSQL_ROOT_PASSWORD=root-ledger \
    -e MYSQL_DATABASE=ledger_test \
    -e MYSQL_USER=ledger \
    -e MYSQL_PASSWORD=ledger \
    -p 127.0.0.1::3306 \
    mysql:8.4 >/dev/null

  wait_for_container "$mysql_container" "mysqladmin ping -h 127.0.0.1 -uroot -proot-ledger --silent"
  local port
  port="$(docker port "$mysql_container" 3306/tcp | sed -E 's/.*:([0-9]+)$/\1/')"
  LEDGER_TEST_MYSQL_DSN="ledger:ledger@tcp(127.0.0.1:${port})/ledger_test?charset=utf8mb4&parseTime=True&loc=UTC"
  export LEDGER_TEST_MYSQL_DSN
}

if [[ -z "${LEDGER_TEST_POSTGRES_DSN:-}" || -z "${LEDGER_TEST_MYSQL_DSN:-}" ]]; then
  if [[ "${RUN_LOCAL_DATABASE_CONTAINERS:-1}" != "1" ]]; then
    echo "LEDGER_TEST_POSTGRES_DSN and LEDGER_TEST_MYSQL_DSN are required when RUN_LOCAL_DATABASE_CONTAINERS=0" >&2
    exit 1
  fi
  if ! command -v docker >/dev/null 2>&1; then
    echo "docker is required to start local database containers" >&2
    exit 1
  fi
  docker version >/dev/null

  [[ -n "${LEDGER_TEST_POSTGRES_DSN:-}" ]] || start_postgres
  [[ -n "${LEDGER_TEST_MYSQL_DSN:-}" ]] || start_mysql
fi

(
  cd "$repo_root/backend"
  go test ./...
)
