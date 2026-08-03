#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

TOTAL_MINIMUM="${BACKEND_COVERAGE_MINIMUM:-64.0}"
REPOSITORY_MINIMUM="${BACKEND_REPOSITORY_COVERAGE_MINIMUM:-90.0}"

coverage_total() {
  local profile="$1"
  go tool cover -func="$profile" | awk '/^total:/ {gsub(/%/, "", $3); print $3}'
}

assert_minimum() {
  local label="$1"
  local actual="$2"
  local minimum="$3"
  python3 - "$label" "$actual" "$minimum" <<'PY'
import sys

label, actual_text, minimum_text = sys.argv[1:]
actual = float(actual_text)
minimum = float(minimum_text)
if actual < minimum:
    raise SystemExit(f"{label} coverage {actual:.1f}% is below required {minimum:.1f}%")
print(f"{label} coverage: {actual:.1f}% (minimum {minimum:.1f}%)")
PY
}

cd "$ROOT_DIR/backend"
go test ./... -count=1 -coverprofile="$TMP_DIR/backend.out"
go test ./internal/repository -count=1 -coverprofile="$TMP_DIR/repository.out"

assert_minimum "Backend total" "$(coverage_total "$TMP_DIR/backend.out")" "$TOTAL_MINIMUM"
assert_minimum "Repository" "$(coverage_total "$TMP_DIR/repository.out")" "$REPOSITORY_MINIMUM"

echo "Backend coverage gate checks passed."
