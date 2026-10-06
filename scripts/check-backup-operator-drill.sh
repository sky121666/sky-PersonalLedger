#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROOF_FILE="${BACKUP_OPERATOR_DRILL_PROOF_FILE:-${BACKUP_OPERATOR_DRILL_FILE:-}}"
if [[ -z "$PROOF_FILE" ]]; then
  echo 'Current machine proof required: set BACKUP_OPERATOR_DRILL_PROOF_FILE to the executed HTTP drill JSON.' >&2
  exit 1
fi
args=(drill --root "$ROOT_DIR" --file "$PROOF_FILE" --max-age-hours "${BACKUP_OPERATOR_DRILL_MAX_AGE_HOURS:-48}")
if [[ -n "${BACKUP_OPERATOR_DRILL_EXPECTED_COMMIT:-}" ]]; then
  args+=(--expected-commit "$BACKUP_OPERATOR_DRILL_EXPECTED_COMMIT")
fi
if [[ "${BACKUP_OPERATOR_DRILL_REQUIRE_CLEAN:-0}" == "1" ]]; then
  args+=(--require-clean)
fi
exec python3 "$ROOT_DIR/scripts/release_evidence.py" "${args[@]}"
