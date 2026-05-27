#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INVENTORY_FILE="${RELEASE_CHANGE_INVENTORY_FILE:-docs/quality/release-change-inventory-2026-05-27.md}"

fail() {
  echo "$1" >&2
  exit 1
}

require_text() {
  local pattern="$1"
  if ! grep -qE "$pattern" "$ROOT_DIR/$INVENTORY_FILE"; then
    fail "Missing required release inventory content: $pattern"
  fi
}

status_paths() {
  git -C "$ROOT_DIR" status --porcelain=v1 | sed -E 's/^...//' | sed -E 's/.* -> //'
}

[[ -f "$ROOT_DIR/$INVENTORY_FILE" ]] || fail "Missing release change inventory: $INVENTORY_FILE"

require_text '^## Conclusion'
require_text '^## Scope Summary'
require_text '^## Required Review Rules'
require_text '^## Intended Change Groups'
require_text '^### Family Accounting'
require_text '^### AI Analysis'
require_text '^### Premium Mobile UI'
require_text '^### Web UI'
require_text '^### Backup, Release, And QA'
require_text '^## Excluded From Release'
require_text '^## Strict Check'

forbidden_status='(^|/)(\.env($|\.)|key\.properties$|local\.properties$|google-services\.json$|GoogleService-Info\.plist$|.*\.(db|db-shm|db-wal|sqlite|sqlite3|apk|ipa|aab|jks|keystore|p12|pem|key|crt|tsbuildinfo)$|node_modules/|\.dart_tool/|\.gradle/|build/|dist/)'
allowed_status='(^|/)(\.env\.example|mobile/android/key\.properties\.example|mobile/android/gradle/wrapper/gradle-wrapper\.jar|mobile/ios/Podfile\.lock|mobile/macos/Podfile\.lock)$'

while IFS= read -r path; do
  [[ -n "$path" ]] || continue
  if [[ "$path" =~ $forbidden_status && ! "$path" =~ $allowed_status ]]; then
    fail "Forbidden generated or secret-like path appears in git status: $path"
  fi
done < <(status_paths)

if [[ "${STRICT_RELEASE_SCOPE:-0}" == "1" ]]; then
  if grep -nE '\bPENDING\b|PENDING REVIEW|<[^>]+>' "$ROOT_DIR/$INVENTORY_FILE" >&2; then
    fail "Release change inventory still contains pending placeholders."
  fi

  missing=0
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    if ! grep -F -- "$path" "$ROOT_DIR/$INVENTORY_FILE" >/dev/null; then
      echo "Changed path is not listed in release change inventory: $path" >&2
      missing=1
    fi
  done < <(status_paths)
  if [[ "$missing" != "0" ]]; then
    fail "Release change inventory does not cover every changed path."
  fi
fi

echo "Release change inventory checks passed."
