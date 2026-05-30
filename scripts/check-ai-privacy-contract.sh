#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

(
  cd "$ROOT_DIR/backend"
  go test ./internal/service ./internal/handler \
    -run 'TestAIProvider|TestAIReportGenerate(MasksNamesAndUsesSeparateCache|StoresAggregatedSnapshotAndContent)|TestAIReportSchedulerGeneratesPreviousWeekOncePerDay|TestBackupDoesNotExportSecurityCredentials|TestBackupRestoreRehearsalIncludesFamilyTransactionsAndAIReports' \
    -count=1
)

echo "AI privacy contract checks passed."
