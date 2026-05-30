#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

(
  cd "$ROOT_DIR/backend"
  go test ./internal/service ./internal/handler -run Health -count=1
)

echo "Runtime health contract checks passed."
