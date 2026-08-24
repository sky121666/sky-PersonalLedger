#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNBOOK_FILE="${FINAL_RELEASE_RUNBOOK_FILE:-docs/quality/final-release-runbook-2026-05-27.md}"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"

fail() {
  echo "$1" >&2
  exit 1
}

require_text() {
  local pattern="$1"
  if ! grep -qE "$pattern" "$ROOT_DIR/$RUNBOOK_FILE"; then
    fail "Missing required final release runbook content: $pattern"
  fi
}

[[ -f "$ROOT_DIR/$RUNBOOK_FILE" ]] || fail "Missing final release runbook: $RUNBOOK_FILE"

if ! grep -Fxq "# Final Release Runbook - v${VERSION}" "$ROOT_DIR/$RUNBOOK_FILE"; then
  fail "Final release runbook version does not match root VERSION: ${VERSION}"
fi

require_text '^## Conclusion'
require_text '^## Preconditions'
require_text '^## 1\. Configure Signing'
require_text '^## 2\. Run Release Workflow'
require_text '^## 3\. Download And Verify Artifacts'
require_text '^## 4\. Mobile Device QA'
require_text '^## 5\. Backup Operator Drill'
require_text '^## 6\. Accessibility Pass'
require_text '^## 7\. Finalize Release Notes'
require_text '^## 8\. Final Gate'
require_text '^## Failure Handling'
require_text 'CHECK_SIGNING_SECRETS=1 ./scripts/check-release-artifacts-preflight.sh'
require_text "RELEASE_ARTIFACT_DIR=artifacts RELEASE_VERSION=${VERSION} REQUIRE_IOS_ARTIFACT=1 VERIFY_ARTIFACT_SIGNATURES=1 ./scripts/check-release-artifact-files.sh"
require_text 'REQUIRE_PHYSICAL_IOS=1 REQUIRE_ANDROID_EMULATOR=1 ./scripts/check-mobile-device-qa-preflight.sh'
require_text 'RUN_ANDROID_E2E=1 ./scripts/check-mobile-device-qa-preflight.sh'
require_text 'STRICT_FINAL_RELEASE=1 ./scripts/check-final-release-gates.sh'
require_text 'docs/quality/release-artifact-evidence-2026-05-27.md'
require_text 'docs/quality/mobile-device-qa-checklist-2026-05-27.md'
require_text 'docs/quality/backup-operator-drill-2026-05-27.md'
require_text 'docs/quality/accessibility-release-evidence-2026-05-27.md'
require_text 'docs/quality/release-notes-candidate-2026-05-27.md'

if [[ "${STRICT_FINAL_RELEASE_RUNBOOK:-0}" == "1" ]]; then
  if grep -nE '\bPENDING\b|<[^>]+>|X\.Y\.Z' "$ROOT_DIR/$RUNBOOK_FILE" >&2; then
    fail "Final release runbook still contains pending placeholders."
  fi
fi

echo "Final release runbook checks passed."
