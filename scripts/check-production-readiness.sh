#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

require_file() {
  local path="$1"
  if [[ ! -f "$ROOT_DIR/$path" ]]; then
    echo "Missing required file: $path" >&2
    exit 1
  fi
}

require_absent() {
  local path="$1"
  if [[ -e "$ROOT_DIR/$path" ]]; then
    echo "Unexpected file exists: $path" >&2
    exit 1
  fi
}

require_absent_text() {
  local path="$1"
  local pattern="$2"
  if grep -Eq "$pattern" "$ROOT_DIR/$path"; then
    echo "Unexpected legacy pattern in $path: $pattern" >&2
    exit 1
  fi
}

require_file "docs/quality/production-readiness-2026-05-27.md"
require_file "docs/quality/release-artifact-evidence-2026-05-27.md"
require_file "docs/quality/docker-release-evidence-2026-05-27.md"
require_file "docs/quality/release-notes-candidate-2026-05-27.md"
require_file "docs/quality/release-change-inventory-2026-05-27.md"
require_file "docs/quality/final-release-runbook-2026-05-27.md"
require_file "docs/quality/accessibility-release-evidence-2026-05-27.md"
require_file "docs/quality/backup-operator-drill-2026-05-27.md"
require_file "docs/android-release-signing.md"
require_file "docs/ios-release-signing.md"
require_file ".github/workflows/android.yml"
require_file ".github/workflows/ios.yml"
require_file ".github/workflows/release.yml"
require_file "scripts/check-public-git-safety.sh"
require_file "scripts/check-backup-restore-rehearsal.sh"
require_file "scripts/check-backup-operator-drill.sh"
require_file "scripts/check-docker-local-smoke.sh"
require_file "scripts/check-docker-compose-local-smoke.sh"
require_file "scripts/check-docker-release-preflight.sh"
require_file "scripts/check-docker-release-evidence.sh"
require_file "scripts/check-runtime-health-contract.sh"
require_file "scripts/check-ai-privacy-contract.sh"
require_file "scripts/check-release-artifacts-preflight.sh"
require_file "scripts/check-release-artifact-files.sh"
require_file "scripts/check-release-notes-candidate.sh"
require_file "scripts/check-release-change-inventory.sh"
require_file "scripts/check-final-release-runbook.sh"
require_file "scripts/check-mobile-device-qa-preflight.sh"
require_file "scripts/check-final-release-gates.sh"
require_file "scripts/verify-mobile-e2e.sh"

require_absent "web/package-lock.json"
require_absent "web/yarn.lock"
require_absent "web/bun.lockb"
require_absent_text "backend/internal/handler/upload.go" 'func \(h \*UploadHandler\) Serve(Static)?\('
require_absent_text "web/src/views/SettingsView.vue" '至少6位|至少6 位|至少 6 位'
require_absent_text "web/src/views/SettingsView.vue" 'v-model="notificationForm\.(dingtalk_secret|smtp_password|webhook_secret)"[^>]*type="text"'
require_absent_text "backend/internal/service/auth.go" 'password must be at least 6 characters'

"$ROOT_DIR/scripts/check-public-git-safety.sh"
"$ROOT_DIR/scripts/check-backup-restore-rehearsal.sh"
"$ROOT_DIR/scripts/check-backup-operator-drill.sh"
"$ROOT_DIR/scripts/check-runtime-health-contract.sh"
"$ROOT_DIR/scripts/check-ai-privacy-contract.sh"
"$ROOT_DIR/scripts/check-docker-release-preflight.sh"
"$ROOT_DIR/scripts/check-docker-release-evidence.sh"
"$ROOT_DIR/scripts/check-release-artifacts-preflight.sh"
"$ROOT_DIR/scripts/check-release-notes-candidate.sh"
"$ROOT_DIR/scripts/check-release-change-inventory.sh"
"$ROOT_DIR/scripts/check-final-release-runbook.sh"
"$ROOT_DIR/scripts/check-mobile-device-qa-preflight.sh"

if [[ "${RUN_EXPENSIVE:-0}" == "1" ]]; then
  (
    cd "$ROOT_DIR/backend"
    go test ./...
  )

  (
    cd "$ROOT_DIR/web"
    pnpm install --frozen-lockfile
    pnpm run build
  )

  (
    cd "$ROOT_DIR/mobile"
    flutter analyze
    flutter test
    flutter test integration_test/premium_screens_smoke_test.dart
  )

  "$ROOT_DIR/scripts/verify-mobile-e2e.sh"

  if [[ "${RUN_DOCKER_LOCAL_SMOKE:-0}" == "1" ]]; then
    "$ROOT_DIR/scripts/check-docker-local-smoke.sh"
  fi

  if [[ "${RUN_DOCKER_COMPOSE_LOCAL_SMOKE:-0}" == "1" ]]; then
    "$ROOT_DIR/scripts/check-docker-compose-local-smoke.sh"
  fi
fi

echo "Production readiness structural checks passed."
