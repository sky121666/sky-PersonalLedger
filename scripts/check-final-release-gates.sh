#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "$1" >&2
  exit 1
}

require_file() {
  local path="$1"
  [[ -f "$ROOT_DIR/$path" ]] || fail "Missing required file: $path"
}

require_no_pending() {
  local path="$1"
  local pending_file
  pending_file="$(mktemp)"
  if grep -nE '\bPENDING\b|AWAITING REAL ARTIFACTS|NOT PROVEN|MISSING|BLOCKED' "$ROOT_DIR/$path" >"$pending_file"; then
    cat "$pending_file" >&2
    rm -f "$pending_file"
    fail "Final release evidence is still incomplete in $path"
  fi
  rm -f "$pending_file"
}

run_strict_check() {
  local label="$1"
  shift

  echo "==> $label"
  if ( "$@" ); then
    echo "PASS: $label"
    return 0
  fi

  echo "FAIL: $label" >&2
  return 1
}

require_file "docs/quality/production-readiness-2026-05-27.md"
require_file "docs/quality/release-artifact-evidence-2026-05-27.md"
require_file "docs/quality/docker-release-evidence-2026-05-27.md"
require_file "docs/quality/release-notes-candidate-2026-05-27.md"
require_file "docs/quality/release-change-inventory-2026-05-27.md"
require_file "docs/quality/final-release-runbook-2026-05-27.md"
require_file "docs/quality/mobile-device-qa-checklist-2026-05-27.md"
require_file "docs/quality/accessibility-release-evidence-2026-05-27.md"
require_file "docs/quality/backup-operator-drill-2026-05-27.md"
require_file "scripts/check-production-readiness.sh"
require_file "scripts/check-backup-operator-drill.sh"
require_file "scripts/check-docker-release-preflight.sh"
require_file "scripts/check-docker-release-evidence.sh"
require_file "scripts/check-release-artifact-files.sh"
require_file "scripts/check-release-notes-candidate.sh"
require_file "scripts/check-release-change-inventory.sh"
require_file "scripts/check-final-release-runbook.sh"
require_file "scripts/check-mobile-device-qa-preflight.sh"
require_file "scripts/check-docker-local-smoke.sh"
require_file "scripts/check-docker-compose-local-smoke.sh"

"$ROOT_DIR/scripts/check-production-readiness.sh"

if [[ "${LOCAL_FINAL_RELEASE:-0}" == "1" || "${SKIP_EXTERNAL_RELEASE_EVIDENCE:-0}" == "1" ]]; then
  local_failures=0

  run_strict_check "release change inventory coverage" \
    env STRICT_RELEASE_SCOPE=1 "$ROOT_DIR/scripts/check-release-change-inventory.sh" || local_failures=1

  run_strict_check "backup operator drill evidence" \
    env STRICT_BACKUP_OPERATOR_DRILL=1 "$ROOT_DIR/scripts/check-backup-operator-drill.sh" || local_failures=1

  run_strict_check "docker local image smoke" \
    "$ROOT_DIR/scripts/check-docker-local-smoke.sh" || local_failures=1

  run_strict_check "docker local compose smoke" \
    "$ROOT_DIR/scripts/check-docker-compose-local-smoke.sh" || local_failures=1

  run_strict_check "working tree whitespace" \
    git -C "$ROOT_DIR" diff --check || local_failures=1

  if [[ "$local_failures" != "0" ]]; then
    fail "Local final release gate failed. See FAIL entries above."
  fi

  echo "Local final release gate checks passed. External release evidence was intentionally skipped."
  exit 0
fi

if [[ "${STRICT_FINAL_RELEASE:-0}" == "1" ]]; then
  strict_failures=0

  run_strict_check "release artifact evidence" \
    require_no_pending "docs/quality/release-artifact-evidence-2026-05-27.md" || strict_failures=1

  run_strict_check "docker release evidence" \
    require_no_pending "docs/quality/docker-release-evidence-2026-05-27.md" || strict_failures=1

  run_strict_check "docker release evidence values" \
    env STRICT_DOCKER_RELEASE_EVIDENCE=1 "$ROOT_DIR/scripts/check-docker-release-evidence.sh" || strict_failures=1

  run_strict_check "release notes final values" \
    env STRICT_RELEASE_NOTES=1 "$ROOT_DIR/scripts/check-release-notes-candidate.sh" || strict_failures=1

  run_strict_check "release change inventory coverage" \
    env STRICT_RELEASE_SCOPE=1 "$ROOT_DIR/scripts/check-release-change-inventory.sh" || strict_failures=1

  run_strict_check "final release runbook values" \
    env STRICT_FINAL_RELEASE_RUNBOOK=1 "$ROOT_DIR/scripts/check-final-release-runbook.sh" || strict_failures=1

  run_strict_check "backup operator drill evidence" \
    env STRICT_BACKUP_OPERATOR_DRILL=1 "$ROOT_DIR/scripts/check-backup-operator-drill.sh" || strict_failures=1

  run_strict_check "mobile physical device checklist" \
    require_no_pending "docs/quality/mobile-device-qa-checklist-2026-05-27.md" || strict_failures=1

  run_strict_check "accessibility release evidence" \
    require_no_pending "docs/quality/accessibility-release-evidence-2026-05-27.md" || strict_failures=1

  run_strict_check "release artifact files" \
    "$ROOT_DIR/scripts/check-release-artifact-files.sh" || strict_failures=1

  run_strict_check "USB iPhone physical preflight" \
    env REQUIRE_PHYSICAL_IOS=1 "$ROOT_DIR/scripts/check-mobile-device-qa-preflight.sh" || strict_failures=1

  if [[ "$strict_failures" != "0" ]]; then
    fail "Strict final release gate failed. See FAIL entries above."
  fi
fi

echo "Final release gate checks passed."
