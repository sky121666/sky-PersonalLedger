#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 "$ROOT_DIR/scripts/release_evidence.py" inventory \
  --root "$ROOT_DIR" \
  --file "${RELEASE_CHANGE_INVENTORY_FILE:-docs/quality/release-change-inventory.json}" \
  --candidate "${RELEASE_INVENTORY_CANDIDATE:-HEAD}"
