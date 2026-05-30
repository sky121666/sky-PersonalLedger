#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOTES_FILE="${RELEASE_NOTES_FILE:-docs/quality/release-notes-candidate-2026-05-27.md}"

fail() {
  echo "$1" >&2
  exit 1
}

require_text() {
  local pattern="$1"
  if ! grep -qE "$pattern" "$ROOT_DIR/$NOTES_FILE"; then
    fail "Missing required release notes content: $pattern"
  fi
}

[[ -f "$ROOT_DIR/$NOTES_FILE" ]] || fail "Missing release notes candidate: $NOTES_FILE"

require_text '^## Personal Ledger v'
require_text '^## Supported Platforms'
require_text '^## Highlights'
require_text '^## Security And Privacy'
require_text '^## Known Limitations'
require_text '^## Upgrade Notes'
require_text '^## Rollback'
require_text '^## Verification Summary'
require_text '^## Release Decision'
require_text 'Android'
require_text 'iOS'
require_text 'Docker image'
require_text 'AI provider'
require_text 'backup'
require_text 'VoiceOver/TalkBack'
require_text 'iOS and Android device validation'
require_text 'STRICT_FINAL_RELEASE=1 ./scripts/check-final-release-gates.sh'

if [[ "${STRICT_RELEASE_NOTES:-0}" == "1" ]]; then
  if grep -nE '\bPENDING\b|PENDING REAL|<[^>]+>' "$ROOT_DIR/$NOTES_FILE" >&2; then
    fail "Release notes still contain pending placeholders."
  fi
fi

echo "Release notes candidate checks passed."
