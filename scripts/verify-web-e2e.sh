#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
backend_pid=""

cleanup() {
  if [[ -n "$backend_pid" ]] && kill -0 "$backend_pid" 2>/dev/null; then
    kill "$backend_pid" 2>/dev/null || true
    wait "$backend_pid" 2>/dev/null || true
  fi
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

for command in go curl python3 pnpm; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "$command is required" >&2
    exit 1
  fi
done

if [[ ! -f "$repo_root/web/dist/index.html" ]]; then
  echo "web/dist is missing; run pnpm --dir web build first" >&2
  exit 1
fi

pick_port() {
  python3 - <<'PY'
import socket

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
}

port="${LEDGER_WEB_E2E_PORT:-$(pick_port)}"
base_url="http://127.0.0.1:$port"
backend_binary="$tmp_dir/ledger-server"
mkdir -p "$tmp_dir/uploads" "$tmp_dir/backups"

(
  cd "$repo_root/backend"
  go build -o "$backend_binary" ./cmd/server
)

(
  LEDGER_SERVER_PORT="$port" \
  LEDGER_SERVER_MODE=debug \
  LEDGER_SERVER_WEB_PATH="$repo_root/web/dist" \
  LEDGER_DATABASE_DRIVER=sqlite \
  LEDGER_DATABASE_PATH="$tmp_dir/ledger.db" \
  LEDGER_SETUP_CONFIG_PATH="$tmp_dir/config.yaml" \
  LEDGER_JWT_SECRET="ledger-web-e2e-secret-32-characters-minimum" \
  LEDGER_STORAGE_UPLOAD_PATH="$tmp_dir/uploads" \
  LEDGER_STORAGE_BACKUP_PATH="$tmp_dir/backups" \
  LEDGER_CORS_ALLOWED_ORIGINS='*' \
  "$backend_binary"
) >"$tmp_dir/backend.log" 2>&1 &
backend_pid="$!"

for _ in $(seq 1 80); do
  if curl -fsS "$base_url/api/v1/health" >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$backend_pid" 2>/dev/null; then
    echo "backend exited before becoming ready" >&2
    sed -n '1,220p' "$tmp_dir/backend.log" >&2 || true
    exit 1
  fi
  sleep 0.25
done

if ! curl -fsS "$base_url/api/v1/health" >/dev/null; then
  echo "backend did not become ready at $base_url" >&2
  sed -n '1,220p' "$tmp_dir/backend.log" >&2 || true
  exit 1
fi

echo "Running Web E2E against isolated backend at $base_url"
(
  cd "$repo_root/web"
  LEDGER_WEB_E2E_BASE_URL="$base_url" \
  LEDGER_WEB_E2E_PASSWORD="${LEDGER_WEB_E2E_PASSWORD:-LedgerWebE2ePass123!}" \
  pnpm test:e2e
)
