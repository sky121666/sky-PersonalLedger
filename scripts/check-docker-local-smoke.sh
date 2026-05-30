#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${DOCKER_LOCAL_SMOKE_IMAGE:-personal-ledger:local-smoke}"
CONTAINER="personal-ledger-local-smoke-$$"
DATA_DIR="$(mktemp -d /tmp/personal-ledger-local-smoke-data.XXXXXX)"

cleanup() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  rm -rf "$DATA_DIR"
}
trap cleanup EXIT

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required" >&2
  exit 1
fi

docker version >/dev/null
mkdir -p "$DATA_DIR/uploads" "$DATA_DIR/backups"

if [[ "${SKIP_DOCKER_BUILD:-0}" != "1" ]]; then
  docker build \
    --build-arg VERSION=local-smoke \
    -t "$IMAGE" \
    "$ROOT_DIR"
fi

docker run -d \
  --name "$CONTAINER" \
  -p 127.0.0.1::8080 \
  -v "$DATA_DIR:/data" \
  -e LEDGER_JWT_SECRET=local-docker-smoke-only-change-me-32-characters \
  -e LEDGER_SERVER_MODE=release \
  -e LEDGER_DATABASE_DRIVER=sqlite \
  -e LEDGER_DATABASE_PATH=/data/ledger.db \
  -e LEDGER_SETUP_CONFIG_PATH=/data/config.yaml \
  "$IMAGE" >/dev/null

port_line=""
for _ in $(seq 1 30); do
  port_line="$(docker port "$CONTAINER" 8080/tcp || true)"
  if [[ -n "$port_line" ]]; then
    break
  fi
  sleep 1
done

if [[ -z "$port_line" ]]; then
  docker logs "$CONTAINER" >&2 || true
  echo "Docker local smoke container did not expose port 8080." >&2
  exit 1
fi

host_port="${port_line##*:}"

health_url="http://127.0.0.1:$host_port/api/v1/health"
for _ in $(seq 1 30); do
  if curl -fsS "$health_url" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

if ! curl -fsS "$health_url" >/dev/null 2>&1; then
  docker logs "$CONTAINER" >&2 || true
  echo "Docker local smoke did not become healthy for $IMAGE." >&2
  exit 1
fi

health_status=""
for _ in $(seq 1 10); do
  health_status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}missing{{end}}' "$CONTAINER")"
  if [[ "$health_status" == "healthy" ]]; then
    break
  fi
  sleep 3
done

if [[ "$health_status" != "healthy" ]]; then
  docker inspect --format '{{json .State.Health}}' "$CONTAINER" >&2 || true
  docker logs "$CONTAINER" >&2 || true
  echo "Docker image HEALTHCHECK did not become healthy; status=${health_status:-unknown}." >&2
  exit 1
fi

for required_path in "$DATA_DIR/ledger.db" "$DATA_DIR/uploads" "$DATA_DIR/backups"; do
  if [[ ! -e "$required_path" ]]; then
    echo "Expected persistent path missing: $required_path" >&2
    exit 1
  fi
done

echo "Docker local smoke checks passed for $IMAGE on 127.0.0.1:$host_port."
echo "Image healthcheck: healthy"
echo "Persistent paths: ledger.db, uploads, backups"
