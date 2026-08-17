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
umask 077

for command in go curl python3; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "$command is required" >&2
    exit 1
  fi
done

pick_port() {
  python3 - <<'PY'
import socket

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
}

port="${LEDGER_BACKUP_REHEARSAL_PORT:-$(pick_port)}"
base_url="http://127.0.0.1:$port/api/v1"
backend_binary="$tmp_dir/ledger-server"
backend_log="$tmp_dir/backend.log"
database_path="$tmp_dir/ledger.db"
upload_path="$tmp_dir/uploads"
backup_path="$tmp_dir/backups"
jwt_secret="ledger-backup-api-rehearsal-secret-32-characters"
password="LedgerBackupRehearsal123!"

mkdir -p "$upload_path" "$backup_path" "$tmp_dir/web"

(
  cd "$repo_root/backend"
  go build -o "$backend_binary" ./cmd/server
)

wait_for_backend() {
  for _ in $(seq 1 80); do
    if curl -fsS "$base_url/health" >/dev/null 2>&1; then
      return 0
    fi
    if [[ -z "$backend_pid" ]] || ! kill -0 "$backend_pid" 2>/dev/null; then
      echo "backend exited before becoming ready" >&2
      sed -n '1,220p' "$backend_log" >&2 || true
      return 1
    fi
    sleep 0.25
  done

  echo "backend did not become ready at $base_url" >&2
  sed -n '1,220p' "$backend_log" >&2 || true
  return 1
}

start_backend() {
  (
    LEDGER_SERVER_PORT="$port" \
    LEDGER_SERVER_MODE=debug \
    LEDGER_SERVER_WEB_PATH="$tmp_dir/web" \
    LEDGER_DATABASE_DRIVER=sqlite \
    LEDGER_DATABASE_PATH="$database_path" \
    LEDGER_SETUP_CONFIG_PATH="$tmp_dir/config.yaml" \
    LEDGER_JWT_SECRET="$jwt_secret" \
    LEDGER_STORAGE_UPLOAD_PATH="$upload_path" \
    LEDGER_STORAGE_BACKUP_PATH="$backup_path" \
    LEDGER_CORS_ALLOWED_ORIGINS='*' \
    "$backend_binary"
  ) >>"$backend_log" 2>&1 &
  backend_pid="$!"
  wait_for_backend
}

stop_backend() {
  if [[ -n "$backend_pid" ]] && kill -0 "$backend_pid" 2>/dev/null; then
    kill "$backend_pid"
    wait "$backend_pid" 2>/dev/null || true
  fi
  backend_pid=""
}

json_value() {
  local path="$1"
  local expression="$2"
  python3 - "$path" "$expression" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle)
for part in sys.argv[2].split("."):
    value = value[part]
print(value)
PY
}

start_backend

curl -fsS \
  -X POST "$base_url/auth/init" \
  -H 'Content-Type: application/json' \
  --data "{\"password\":\"$password\"}" \
  -o "$tmp_dir/auth.json"

access_token="$(json_value "$tmp_dir/auth.json" 'data.access_token')"
auth_header="Authorization: Bearer $access_token"

curl -fsS \
  -X POST "$base_url/accounts" \
  -H "$auth_header" \
  -H 'Content-Type: application/json' \
  --data '{"name":"Backup API Account","type":"cash","icon":"banknote","color":"#007AFF","initial_balance":0,"remark":"backup-api-marker"}' \
  -o "$tmp_dir/account.json"
account_id="$(json_value "$tmp_dir/account.json" 'data.id')"

curl -fsS \
  -X POST "$base_url/transactions" \
  -H "$auth_header" \
  -H 'Content-Type: application/json' \
  --data "{\"type\":\"expense\",\"amount\":12.34,\"account_id\":\"$account_id\",\"transaction_date\":\"2026-08-03T12:00:00+08:00\",\"remark\":\"backup-api-transaction\"}" \
  -o "$tmp_dir/transaction.json"
transaction_id="$(json_value "$tmp_dir/transaction.json" 'data.id')"

curl -fsS \
  -X POST "$base_url/api-tokens" \
  -H "$auth_header" \
  -H 'Content-Type: application/json' \
  --data '{"name":"Backup rehearsal token","expires_in_days":30,"scopes":["ledger:read"]}' \
  -o "$tmp_dir/api-token.json"
api_token="$(json_value "$tmp_dir/api-token.json" 'data.token')"

curl -fsS \
  "$base_url/backup" \
  -H "$auth_header" \
  -o "$tmp_dir/backup.json"

python3 - \
  "$tmp_dir/backup.json" \
  "$tmp_dir/auth.json" \
  "$tmp_dir/api-token.json" \
  "$account_id" \
  "$transaction_id" \
  "$password" <<'PY'
import json
import sys

backup_path, auth_path, api_token_path, account_id, transaction_id, password = sys.argv[1:]
with open(backup_path, encoding="utf-8") as handle:
    backup = json.load(handle)
with open(auth_path, encoding="utf-8") as handle:
    auth = json.load(handle)["data"]
with open(api_token_path, encoding="utf-8") as handle:
    api_token = json.load(handle)["data"]

accounts = {item["id"]: item for item in backup.get("accounts", [])}
transactions = {item["id"]: item for item in backup.get("transactions", [])}
if accounts.get(account_id, {}).get("name") != "Backup API Account":
    raise SystemExit("exported backup is missing the rehearsal account")
if transactions.get(transaction_id, {}).get("remark") != "backup-api-transaction":
    raise SystemExit("exported backup is missing the rehearsal transaction")

serialized = json.dumps(backup, ensure_ascii=False, separators=(",", ":"))
for forbidden_value in (
    password,
    auth["access_token"],
    auth["refresh_token"],
    api_token["token"],
    api_token["token_prefix"],
):
    if forbidden_value and forbidden_value in serialized:
        raise SystemExit("backup exported authentication credential material")

for forbidden_key in (
    '"password_hash"',
    '"refresh_tokens"',
    '"api_tokens"',
    '"smtp_password"',
    '"webhook_secret"',
    '"dingtalk_secret"',
):
    if forbidden_key in serialized:
        raise SystemExit(f"backup exported forbidden credential field {forbidden_key}")
PY

curl -fsS \
  -X PATCH "$base_url/accounts/$account_id" \
  -H "$auth_header" \
  -H 'Content-Type: application/json' \
  --data '{"name":"Mutated Account"}' \
  -o "$tmp_dir/mutated-account.json"
curl -fsS \
  -X DELETE "$base_url/transactions/$transaction_id" \
  -H "$auth_header" \
  -o "$tmp_dir/deleted-transaction.json"

curl -fsS \
  "$base_url/accounts/$account_id" \
  -H "$auth_header" \
  -o "$tmp_dir/mutated-account-state.json"
deleted_status="$(curl -sS \
  -o "$tmp_dir/deleted-transaction-state.json" \
  -w '%{http_code}' \
  "$base_url/transactions/$transaction_id" \
  -H "$auth_header")"

python3 - "$tmp_dir/mutated-account-state.json" "$deleted_status" <<'PY'
import json
import sys
from decimal import Decimal

with open(sys.argv[1], encoding="utf-8") as handle:
    account = json.load(handle)["data"]
if account.get("name") != "Mutated Account":
    raise SystemExit("pre-restore account mutation did not persist")
if Decimal(str(account.get("current_balance"))) != Decimal("0"):
    raise SystemExit("pre-restore transaction deletion did not restore the account balance")
if sys.argv[2] != "404":
    raise SystemExit(f"pre-restore transaction still exists (HTTP {sys.argv[2]})")
PY

curl -fsS \
  -X POST "$base_url/restore" \
  -H "$auth_header" \
  -F "file=@$tmp_dir/backup.json;type=application/json" \
  -o "$tmp_dir/restore.json"

python3 - "$tmp_dir/restore.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    response = json.load(handle)
if response.get("code") != 0:
    raise SystemExit(f"restore API returned an error: {response}")
if not response.get("data", {}).get("pre_restore_backup"):
    raise SystemExit("restore API did not create a pre-restore safety backup")
PY

stop_backend
start_backend

curl -fsS \
  "$base_url/accounts?include_archived=true" \
  -H "$auth_header" \
  -o "$tmp_dir/restored-accounts.json"
curl -fsS \
  "$base_url/transactions?include_system=true&page_size=100" \
  -H "$auth_header" \
  -o "$tmp_dir/restored-transactions.json"
curl -fsS \
  "$base_url/accounts?include_archived=true" \
  -H "Authorization: Bearer $api_token" \
  -o "$tmp_dir/api-token-accounts.json"

python3 - \
  "$tmp_dir/restored-accounts.json" \
  "$tmp_dir/restored-transactions.json" \
  "$tmp_dir/api-token-accounts.json" \
  "$account_id" \
  "$transaction_id" <<'PY'
import json
import sys
from decimal import Decimal

accounts_path, transactions_path, token_accounts_path, account_id, transaction_id = sys.argv[1:]
with open(accounts_path, encoding="utf-8") as handle:
    accounts_response = json.load(handle)
with open(transactions_path, encoding="utf-8") as handle:
    transactions_response = json.load(handle)
with open(token_accounts_path, encoding="utf-8") as handle:
    token_accounts_response = json.load(handle)

accounts = {item["id"]: item for item in accounts_response["data"]["list"]}
transactions = {item["id"]: item for item in transactions_response["data"]["list"]}
account = accounts.get(account_id)
transaction = transactions.get(transaction_id)
if account is None or account.get("name") != "Backup API Account":
    raise SystemExit("account was not restored after backend restart")
if Decimal(str(account.get("current_balance"))) != Decimal("-12.34"):
    raise SystemExit(f"restored account balance is incorrect: {account.get('current_balance')}")
if transaction is None or transaction.get("remark") != "backup-api-transaction":
    raise SystemExit("transaction was not restored after backend restart")
if Decimal(str(transaction.get("amount"))) != Decimal("12.34"):
    raise SystemExit(f"restored transaction amount is incorrect: {transaction.get('amount')}")
if token_accounts_response.get("code") != 0:
    raise SystemExit("existing API token no longer works after restore and restart")
if not any(item.get("id") == account_id for item in token_accounts_response["data"]["list"]):
    raise SystemExit("API token cannot read restored account data")
PY

echo "Backup HTTP export, restore, restart, credential isolation, and API-token checks passed."
