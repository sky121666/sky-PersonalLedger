#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

(
  cd "$ROOT_DIR/backend"
  go test ./internal/service -run 'TestBackupRestoreRehearsalIncludesFamilyTransactionsAndAIReports|TestBackupDoesNotExportSecurityCredentials' -count=1
)

echo "Backup restore rehearsal checks passed."
