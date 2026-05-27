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
fi

if [[ -n "$IMAGE" ]]; then
  require_tool docker
  docker manifest inspect "$IMAGE" >/tmp/personal-ledger-docker-manifest.json
  grep -q '"architecture": "amd64"' /tmp/personal-ledger-docker-manifest.json || fail "Docker manifest missing linux/amd64: $IMAGE"
  grep -q '"architecture": "arm64"' /tmp/personal-ledger-docker-manifest.json || fail "Docker manifest missing linux/arm64: $IMAGE"
  rm -f /tmp/personal-ledger-docker-manifest.json
  echo "Docker manifest checks passed for $IMAGE."
fi

if [[ "$RUN_SMOKE" == "1" ]]; then
  [[ -n "$IMAGE" ]] || fail "DOCKER_RELEASE_IMAGE is required when RUN_DOCKER_RELEASE_SMOKE=1."
  require_tool docker

  smoke_dir="$(mktemp -d /tmp/personal-ledger-docker-smoke.XXXXXX)"
  cleanup() {
    (
      cd "$smoke_dir" 2>/dev/null && docker compose down -v >/dev/null 2>&1
    ) || true
    rm -rf "$smoke_dir"
  }
  trap cleanup EXIT

  mkdir -p "$smoke_dir/data"
  cat >"$smoke_dir/docker-compose.yml" <<EOF
services:
  personal-ledger:
    image: $IMAGE
    ports:
      - "18080:8080"
    volumes:
      - ./data:/data
    environment:
      - LEDGER_JWT_SECRET=local-docker-smoke-only-change-me-32-characters
      - LEDGER_SERVER_MODE=release
      - LEDGER_DATABASE_DRIVER=sqlite
      - LEDGER_DATABASE_PATH=/data/ledger.db
      - LEDGER_SETUP_CONFIG_PATH=/data/config.yaml
      - TZ=Asia/Shanghai
EOF

  (
    cd "$smoke_dir"
    docker compose pull
    docker compose up -d
  )

  for _ in $(seq 1 30); do
    if curl -fsS http://127.0.0.1:18080/ >/dev/null 2>&1; then
      echo "Docker release smoke checks passed for $IMAGE."
      exit 0
    fi
    sleep 2
  done

  docker compose -f "$smoke_dir/docker-compose.yml" logs >&2 || true
  fail "Docker release smoke did not become healthy: $IMAGE"
fi

echo "Docker release evidence checks passed."
