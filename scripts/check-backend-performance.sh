#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR/backend"
go test ./internal/database -run '^TestOperationalQueryIndexesExistAndDriveSQLitePlans$' -count=1
go test ./internal/repository -run '^$' -bench '^BenchmarkTransactionRepository' -benchtime=3x -count=1

echo "Backend performance contract checks passed."
