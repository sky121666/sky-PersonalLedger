#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${DOCKER_LOCAL_SMOKE_IMAGE:-personal-ledger:local-smoke}"
SMOKE_DIR="$(mktemp -d /tmp/personal-ledger-compose-smoke.XXXXXX)"
PORT=""

cleanup() {
  (
    cd "$SMOKE_DIR" 2>/dev/null && docker compose down -v >/dev/null 2>&1
  ) || true
  rm -rf "$SMOKE_DIR"
}
trap cleanup EXIT

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "$1 is required" >&2
    exit 1
  fi
}

pick_port() {
  python3 - <<'PY'
import socket

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
}

require_tool docker
require_tool curl
require_tool python3

docker version >/dev/null

if [[ "${SKIP_DOCKER_BUILD:-0}" != "1" ]]; then
  docker build \
    --build-arg VERSION=local-compose-smoke \
    -t "$IMAGE" \
    "$ROOT_DIR"
elif ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "Docker image not found and SKIP_DOCKER_BUILD=1: $IMAGE" >&2
  exit 1
fi

if env -u LEDGER_JWT_SECRET docker compose -f "$ROOT_DIR/docker-compose.yml" config >/dev/null 2>&1; then
  echo "docker-compose.yml did not require LEDGER_JWT_SECRET." >&2
  exit 1
fi

PORT="$(pick_port)"
mkdir -p "$SMOKE_DIR/data"
cat >"$SMOKE_DIR/docker-compose.yml" <<EOF
services:
  personal-ledger:
    image: $IMAGE
    ports:
      - "127.0.0.1:$PORT:8080"
    volumes:
      - ./data:/data
    environment:
      - LEDGER_JWT_SECRET=local-compose-smoke-only-32-characters
      - LEDGER_SERVER_MODE=release
      - LEDGER_DATABASE_DRIVER=sqlite
      - LEDGER_DATABASE_PATH=/data/ledger.db
      - LEDGER_SETUP_CONFIG_PATH=/data/config.yaml
      - LEDGER_STORAGE_UPLOAD_PATH=/data/uploads
      - LEDGER_STORAGE_BACKUP_PATH=/data/backups
      - TZ=Asia/Shanghai
EOF

(
  cd "$SMOKE_DIR"
  docker compose up -d
)

health_url="http://127.0.0.1:$PORT/api/v1/health"
for _ in $(seq 1 30); do
  if curl -fsS "$health_url" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

if ! curl -fsS "$health_url" >/dev/null 2>&1; then
  docker compose -f "$SMOKE_DIR/docker-compose.yml" logs >&2 || true
  echo "Docker compose local smoke did not become healthy." >&2
  exit 1
fi

for required_path in "$SMOKE_DIR/data/ledger.db" "$SMOKE_DIR/data/uploads"; do
  if [[ ! -e "$required_path" ]]; then
    echo "Expected persistent path missing: $required_path" >&2
    exit 1
  fi
done

echo "Docker compose local smoke checks passed for $IMAGE on 127.0.0.1:$PORT."
echo "JWT guard: PASS"
echo "Persistent paths: ledger.db, uploads"
