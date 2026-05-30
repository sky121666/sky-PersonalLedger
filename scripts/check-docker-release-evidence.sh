#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVIDENCE_FILE="${DOCKER_RELEASE_EVIDENCE_FILE:-docs/quality/docker-release-evidence-2026-05-27.md}"
IMAGE="${DOCKER_RELEASE_IMAGE:-}"
RUN_SMOKE="${RUN_DOCKER_RELEASE_SMOKE:-0}"

fail() {
  echo "$1" >&2
  exit 1
}

require_text() {
  local pattern="$1"
  if ! grep -qE "$pattern" "$ROOT_DIR/$EVIDENCE_FILE"; then
    fail "Missing required Docker release evidence content: $pattern"
  fi
}

require_tool() {
  local name="$1"
  command -v "$name" >/dev/null 2>&1 || fail "Missing required tool: $name"
}

pick_port() {
  python3 - <<'PY'
import socket

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
}

[[ -f "$ROOT_DIR/$EVIDENCE_FILE" ]] || fail "Missing Docker release evidence file: $EVIDENCE_FILE"

require_text '^## Conclusion'
require_text '^## Preflight'
require_text '^## Image Evidence'
require_text '^## Deployment Smoke'
require_text '^## Release Decision'
require_text './scripts/check-docker-release-preflight.sh'
require_text './scripts/check-docker-local-smoke.sh'
require_text 'linux/amd64'
require_text 'linux/arm64'
require_text 'LEDGER_JWT_SECRET'

if [[ "${STRICT_DOCKER_RELEASE_EVIDENCE:-0}" == "1" ]]; then
  if grep -nE '\bPENDING\b|<[^>]+>|X\.Y\.Z' "$ROOT_DIR/$EVIDENCE_FILE" >&2; then
    fail "Docker release evidence still contains pending placeholders."
  fi
  [[ -n "$IMAGE" ]] || fail "DOCKER_RELEASE_IMAGE is required when STRICT_DOCKER_RELEASE_EVIDENCE=1."
  [[ "$RUN_SMOKE" == "1" ]] || fail "RUN_DOCKER_RELEASE_SMOKE=1 is required when STRICT_DOCKER_RELEASE_EVIDENCE=1."
fi

if [[ -n "$IMAGE" ]]; then
  require_tool docker
  manifest_file="$(mktemp /tmp/personal-ledger-docker-manifest.XXXXXX.json)"
  if ! docker manifest inspect "$IMAGE" >"$manifest_file"; then
    rm -f "$manifest_file"
    fail "Docker manifest inspect failed: $IMAGE"
  fi
  if ! grep -q '"architecture": "amd64"' "$manifest_file"; then
    rm -f "$manifest_file"
    fail "Docker manifest missing linux/amd64: $IMAGE"
  fi
  if ! grep -q '"architecture": "arm64"' "$manifest_file"; then
    rm -f "$manifest_file"
    fail "Docker manifest missing linux/arm64: $IMAGE"
  fi
  rm -f "$manifest_file"
  echo "Docker manifest checks passed for $IMAGE."
fi

if [[ "$RUN_SMOKE" == "1" ]]; then
  [[ -n "$IMAGE" ]] || fail "DOCKER_RELEASE_IMAGE is required when RUN_DOCKER_RELEASE_SMOKE=1."
  require_tool docker
  require_tool curl
  require_tool python3

  smoke_dir="$(mktemp -d /tmp/personal-ledger-docker-smoke.XXXXXX)"
  smoke_port="$(pick_port)"
  cleanup() {
    (
      cd "$smoke_dir" 2>/dev/null && docker compose down -v >/dev/null 2>&1
    ) || true
    rm -rf "$smoke_dir"
  }
  trap cleanup EXIT

  mkdir -p "$smoke_dir/data/uploads" "$smoke_dir/data/backups"
  cat >"$smoke_dir/docker-compose.yml" <<EOF
services:
  personal-ledger:
    image: $IMAGE
    ports:
      - "127.0.0.1:$smoke_port:8080"
    volumes:
      - ./data:/data
    environment:
      - LEDGER_JWT_SECRET=local-docker-smoke-only-change-me-32-characters
      - LEDGER_SERVER_MODE=release
      - LEDGER_DATABASE_DRIVER=sqlite
      - LEDGER_DATABASE_PATH=/data/ledger.db
      - LEDGER_SETUP_CONFIG_PATH=/data/config.yaml
      - LEDGER_STORAGE_UPLOAD_PATH=/data/uploads
      - LEDGER_STORAGE_BACKUP_PATH=/data/backups
      - TZ=Asia/Shanghai
EOF

  (
    cd "$smoke_dir"
    docker compose pull
    docker compose up -d
  )

  health_url="http://127.0.0.1:$smoke_port/api/v1/health"
  for _ in $(seq 1 30); do
    if curl -fsS "$health_url" >/dev/null 2>&1; then
      break
    fi
    sleep 2
  done

  if ! curl -fsS "$health_url" >/dev/null 2>&1; then
    docker compose -f "$smoke_dir/docker-compose.yml" logs >&2 || true
    fail "Docker release smoke did not become healthy: $IMAGE"
  fi

  container_id="$(cd "$smoke_dir" && docker compose ps -q personal-ledger)"
  health_status=""
  for _ in $(seq 1 10); do
    health_status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}missing{{end}}' "$container_id")"
    if [[ "$health_status" == "healthy" ]]; then
      break
    fi
    sleep 3
  done

  if [[ "$health_status" != "healthy" ]]; then
    docker inspect --format '{{json .State.Health}}' "$container_id" >&2 || true
    docker compose -f "$smoke_dir/docker-compose.yml" logs >&2 || true
    fail "Docker release image HEALTHCHECK did not become healthy; status=${health_status:-unknown}: $IMAGE"
  fi

  for required_path in "$smoke_dir/data/ledger.db" "$smoke_dir/data/uploads" "$smoke_dir/data/backups"; do
    if [[ ! -e "$required_path" ]]; then
      fail "Expected persistent path missing: $required_path"
    fi
  done

  echo "Docker release smoke checks passed for $IMAGE on 127.0.0.1:$smoke_port."
  echo "Image healthcheck: healthy"
  echo "Persistent paths: ledger.db, uploads, backups"
fi

echo "Docker release evidence checks passed."
