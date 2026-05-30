#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
SOURCE_PID=""
TARGET_PID=""
AI_PID=""

cleanup() {
  for pid in "$SOURCE_PID" "$TARGET_PID" "$AI_PID"; do
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  done
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

require_command() {
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

wait_for_http() {
  local url="$1"
  local pid="$2"
  local log_file="$3"
  for _ in $(seq 1 100); do
    if curl -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "process exited before becoming ready: $url" >&2
      sed -n '1,220p' "$log_file" >&2 || true
      return 1
    fi
    sleep 0.25
  done
  echo "timed out waiting for $url" >&2
  sed -n '1,220p' "$log_file" >&2 || true
  return 1
}

start_backend() {
  local name="$1"
  local port="$2"
  local data_dir="$TMP_DIR/$name"
  mkdir -p "$data_dir/uploads" "$data_dir/backups" "$data_dir/web"
  (
    cd "$ROOT_DIR/backend"
    LEDGER_SERVER_PORT="$port" \
    LEDGER_SERVER_MODE=debug \
    LEDGER_SERVER_WEB_PATH="$data_dir/web" \
    LEDGER_DATABASE_DRIVER=sqlite \
    LEDGER_DATABASE_PATH="$data_dir/ledger.db" \
    LEDGER_SETUP_CONFIG_PATH="$data_dir/config.yaml" \
    LEDGER_JWT_SECRET="ledger-local-drill-secret-32-characters-$name" \
    LEDGER_STORAGE_UPLOAD_PATH="$data_dir/uploads" \
    LEDGER_STORAGE_BACKUP_PATH="$data_dir/backups" \
    LEDGER_CORS_ALLOWED_ORIGINS='*' \
    go run ./cmd/server
  ) >"$data_dir/backend.log" 2>&1 &
  local pid="$!"
  wait_for_http "http://127.0.0.1:$port/api/v1/auth/status" "$pid" "$data_dir/backend.log"
  printf '%s' "$pid"
}

start_fake_ai() {
  local port="$1"
  local log_file="$TMP_DIR/fake-ai.log"
  python3 - "$port" >"$log_file" 2>&1 <<'PY' &
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        if length:
            self.rfile.read(length)
        body = {
            "choices": [
                {
                    "message": {
                        "content": "本周财务总结：家庭支出结构稳定，建议继续跟踪成员维度。"
                    }
                }
            ]
        }
        payload = json.dumps(body).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, format, *args):
        return

server = ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), Handler)
server.serve_forever()
PY
  local pid="$!"
  for _ in $(seq 1 40); do
    if curl -fsS -X POST "http://127.0.0.1:$port/v1/chat/completions" -d '{}' >/dev/null 2>&1; then
      printf '%s' "$pid"
      return 0
    fi
    sleep 0.25
  done
  echo "timed out waiting for fake AI server" >&2
  sed -n '1,120p' "$log_file" >&2 || true
  return 1
}

api() {
  local method="$1"
  local base_url="$2"
  local token="$3"
  local path="$4"
  local body="${5:-}"
  if [[ -n "$body" ]]; then
    curl -fsS -X "$method" \
      -H "Authorization: Bearer $token" \
      -H "Content-Type: application/json" \
      "$base_url$path" \
      -d "$body"
  else
    curl -fsS -X "$method" \
      -H "Authorization: Bearer $token" \
      "$base_url$path"
  fi
}

init_instance() {
  local base_url="$1"
  local password="$2"
  curl -fsS -X POST \
    -H "Content-Type: application/json" \
    "$base_url/api/v1/auth/init" \
    -d "$(jq -nc --arg password "$password" '{password:$password}')" |
    jq -r '.data.access_token'
}

require_command go
require_command curl
require_command jq
require_command python3

SOURCE_PORT="$(pick_port)"
TARGET_PORT="$(pick_port)"
AI_PORT="$(pick_port)"
SOURCE_BASE="http://127.0.0.1:$SOURCE_PORT"
TARGET_BASE="http://127.0.0.1:$TARGET_PORT"
PASSWORD="LedgerOperatorDrill123!"
AI_API_KEY="operator-drill-api-key"
BACKUP_FILE="$TMP_DIR/backup-release-drill.json"

AI_PID="$(start_fake_ai "$AI_PORT")"
SOURCE_PID="$(start_backend source "$SOURCE_PORT")"
TARGET_PID="$(start_backend target "$TARGET_PORT")"

SOURCE_TOKEN="$(init_instance "$SOURCE_BASE" "$PASSWORD")"
TARGET_TOKEN="$(init_instance "$TARGET_BASE" "$PASSWORD")"

member_json="$(api POST "$SOURCE_BASE" "$SOURCE_TOKEN" /api/v1/family/members '{"name":"Operator Drill Member","relationship":"family","color":"#2F80ED","is_default":true}')"
member_id="$(jq -r '.data.id' <<<"$member_json")"

account_json="$(api POST "$SOURCE_BASE" "$SOURCE_TOKEN" /api/v1/accounts '{"name":"Operator Drill Cash","type":"cash","initial_balance":1000,"icon":"wallet","color":"#2F80ED"}')"
account_id="$(jq -r '.data.id' <<<"$account_json")"

category_json="$(api POST "$SOURCE_BASE" "$SOURCE_TOKEN" /api/v1/categories '{"name":"Operator Drill Expense","type":"expense","icon":"shopping-cart","color":"#EB5757"}')"
category_id="$(jq -r '.data.id' <<<"$category_json")"

tx_payload="$(jq -nc \
  --arg account_id "$account_id" \
  --arg category_id "$category_id" \
  --arg member_id "$member_id" \
  '{type:"expense",amount:123.45,account_id:$account_id,category_id:$category_id,member_id:$member_id,paid_by_member_id:$member_id,transaction_date:"2026-05-27",remark:"operator drill transaction"}')"
tx_json="$(api POST "$SOURCE_BASE" "$SOURCE_TOKEN" /api/v1/transactions "$tx_payload")"
tx_id="$(jq -r '.data.id' <<<"$tx_json")"

provider_payload="$(jq -nc \
  --arg base_url "http://127.0.0.1:$AI_PORT" \
  --arg api_key "$AI_API_KEY" \
  '{name:"Operator Drill AI",provider_type:"openai_compatible",base_url:$base_url,api_key:$api_key,model:"drill-model",enabled:true}')"
provider_json="$(api POST "$SOURCE_BASE" "$SOURCE_TOKEN" /api/v1/ai/providers "$provider_payload")"
provider_id="$(jq -r '.data.id' <<<"$provider_json")"

report_payload="$(jq -nc \
  --arg provider_id "$provider_id" \
  '{report_type:"weekly",provider_id:$provider_id,period_start:"2026-05-25",period_end:"2026-05-31"}')"
report_json="$(api POST "$SOURCE_BASE" "$SOURCE_TOKEN" /api/v1/ai/reports/generate "$report_payload")"
report_id="$(jq -r '.data.id' <<<"$report_json")"
report_status="$(jq -r '.data.status' <<<"$report_json")"
if [[ "$report_status" != "completed" ]]; then
  echo "AI report did not complete: $report_json" >&2
  exit 1
fi

api GET "$SOURCE_BASE" "$SOURCE_TOKEN" /api/v1/backup >"$BACKUP_FILE"

for forbidden in "$PASSWORD" "$AI_API_KEY" password_hash refresh_token api_token api_key APIKey; do
  if grep -q "$forbidden" "$BACKUP_FILE"; then
    echo "backup leaked forbidden marker: $forbidden" >&2
    exit 1
  fi
done

curl -fsS -X POST \
  -H "Authorization: Bearer $TARGET_TOKEN" \
  -F "file=@$BACKUP_FILE" \
  "$TARGET_BASE/api/v1/restore" >/dev/null

target_members="$(api GET "$TARGET_BASE" "$TARGET_TOKEN" /api/v1/family/members)"
target_txs="$(api GET "$TARGET_BASE" "$TARGET_TOKEN" "/api/v1/transactions?page=1&page_size=20")"
target_reports="$(api GET "$TARGET_BASE" "$TARGET_TOKEN" /api/v1/ai/reports)"
target_providers="$(api GET "$TARGET_BASE" "$TARGET_TOKEN" /api/v1/ai/providers)"
target_summary="$(api GET "$TARGET_BASE" "$TARGET_TOKEN" "/api/v1/family/summary?month=2026-05")"

jq -e --arg member_id "$member_id" '.data[] | select(.id == $member_id and .name == "Operator Drill Member" and .is_default == true)' <<<"$target_members" >/dev/null
jq -e --arg tx_id "$tx_id" --arg member_id "$member_id" '.data.list[] | select(.id == $tx_id and .member_id == $member_id and .amount == 123.45)' <<<"$target_txs" >/dev/null
jq -e --arg report_id "$report_id" '.data[] | select(.id == $report_id and .status == "completed" and .provider_name == "Operator Drill AI")' <<<"$target_reports" >/dev/null
jq -e '.data | length == 0' <<<"$target_providers" >/dev/null
jq -e '.data.total_expense == 123.45' <<<"$target_summary" >/dev/null

echo "Backup operator local drill passed."
echo "Source: $SOURCE_BASE"
echo "Target: $TARGET_BASE"
echo "Backup file bytes: $(wc -c <"$BACKUP_FILE" | tr -d ' ')"
echo "Family member: $member_id"
echo "Transaction: $tx_id"
echo "AI report: $report_id"
