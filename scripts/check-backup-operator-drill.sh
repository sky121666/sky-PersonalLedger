#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRILL_FILE="${BACKUP_OPERATOR_DRILL_FILE:-docs/quality/backup-operator-drill-2026-05-27.md}"

fail() {
  echo "$1" >&2
  exit 1
}

require_text() {
  local pattern="$1"
  if ! grep -qE "$pattern" "$ROOT_DIR/$DRILL_FILE"; then
    fail "Missing required backup drill content: $pattern"
  fi
}

[[ -f "$ROOT_DIR/$DRILL_FILE" ]] || fail "Missing backup operator drill file: $DRILL_FILE"

require_text '^## Conclusion'
require_text '^## Scope'
require_text '^## Required Environment'
require_text '^## Drill Steps'
require_text '^## Suggested API Drill'
require_text '^## Secret Inspection'
require_text '^## Release Decision'
require_text 'family member'
require_text 'member-linked transaction'
require_text 'AI report'
require_text 'AI provider API key'
require_text '/api/v1/backup'
require_text '/api/v1/restore'

if [[ "${STRICT_BACKUP_OPERATOR_DRILL:-0}" == "1" ]]; then
  if grep -nE '\bPENDING\b|<[^>]+>' "$ROOT_DIR/$DRILL_FILE" >&2; then
    fail "Backup operator drill still contains pending placeholders."
  fi
fi

echo "Backup operator drill checks passed."
