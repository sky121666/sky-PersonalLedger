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

require_text() {
  local path="$1"
  local pattern="$2"
  if ! grep -Eq "$pattern" "$ROOT_DIR/$path"; then
    echo "Missing required pattern in $path: $pattern" >&2
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

require_absent_text "backend/internal/service/health.go" 'Message: err\.Error\(\)'
require_text "backend/internal/service/health.go" 'database check failed'
require_text "backend/internal/service/health.go" 'directory is not accessible'
require_absent_text "backend/internal/middleware/middleware.go" 'response\.Unauthorized\(c, err\.Error\(\)\)'
require_absent "web/package-lock.json"
require_absent "web/yarn.lock"
require_absent "web/bun.lockb"
require_absent_text "backend/internal/handler/upload.go" 'func \(h \*UploadHandler\) Serve(Static)?\('
require_absent_text "backend/internal/handler/upload.go" 'response\.InternalError\(c, err\.Error\(\)\)'
require_text "backend/internal/handler/upload.go" 'failed to list uploaded files'
require_absent_text "backend/cmd/server/main.go" 'absUploadPath, _ := filepath\.Abs'
require_absent_text "backend/cmd/server/main.go" 'absRootPath, _ := filepath\.Abs'
require_absent_text "backend/internal/service/upload.go" 'absUploadPath, _ := filepath\.Abs'
require_absent_text "backend/internal/handler/backup.go" 'response\.InternalError\(c, err\.Error\(\)\)'
require_absent_text "backend/internal/handler/backup.go" 'failed to create pre-restore backup: '
require_absent_text "backend/internal/handler/backup.go" 'ErrInvalidBackupFormat.*err\.Error\(\)'
require_text "backend/internal/handler/backup.go" 'failed to create pre-restore backup'
require_text "backend/internal/handler/backup.go" 'ErrInvalidBackupFormat\.Error\(\)'
require_absent_text "backend/internal/handler/auth.go" 'response\.InternalError\(c, err\.Error\(\)\)'
require_absent_text "backend/internal/handler/auth.go" 'response\.Unauthorized\(c, err\.Error\(\)\)'
require_text "backend/internal/handler/auth.go" 'failed to load profile'
require_absent_text "backend/internal/handler/setup.go" 'failed to write setup config: '
require_absent_text "backend/internal/handler/setup.go" 'database test failed: '
require_text "backend/internal/handler/setup.go" 'failed to write setup config'
require_text "backend/internal/handler/setup.go" 'database test failed'
require_absent_text "backend/internal/handler/transaction.go" 'response\.InternalError\(c, err\.Error\(\)\)'
require_text "backend/internal/handler/transaction.go" 'failed to list transactions'
require_absent_text "backend/internal/handler/transaction.go" 't, _ := time\.Parse'
require_text "backend/internal/handler/transaction.go" 'invalid start date'
require_absent_text "backend/internal/service/transaction.go" 't, _ := time\.Parse'
require_absent_text "backend/internal/handler/ai.go" 'response\.InternalError\(c, err\.Error\(\)\)'
require_absent_text "backend/internal/handler/ai.go" 'response\.Error\(c, .*err\.Error\(\)\)'
require_text "backend/internal/handler/ai.go" 'failed to process AI provider request'
require_text "backend/internal/service/ai_report.go" 'AI provider request failed; check provider configuration or network'
require_absent_text "backend/internal/handler/account.go" 'response\.InternalError\(c, err\.Error\(\)\)'
require_text "backend/internal/handler/account.go" 'failed to summarize accounts'
require_absent_text "backend/internal/handler/lending.go" 'response\.InternalError\(c, err\.Error\(\)\)'
require_text "backend/internal/handler/lending.go" 'failed to summarize lendings'
require_absent_text "backend/internal/handler/statistics.go" 'response\.InternalError\(c, err\.Error\(\)\)'
require_text "backend/internal/handler/statistics.go" 'failed to load statistics overview'
require_absent_text "backend/internal/handler/system.go" 'response\.InternalError\(c, err\.Error\(\)\)'
require_text "backend/internal/handler/system.go" 'failed to load entry path'
require_absent_text "backend/internal/handler/account_log.go" 'response\.InternalError\(c, err\.Error\(\)\)'
require_text "backend/internal/handler/account_log.go" 'failed to load account logs'
require_absent_text "backend/internal/handler/export.go" 'err\.Error\(\)'
require_text "backend/internal/handler/export.go" 'failed to export transactions'
require_absent_text "backend/internal/handler/category.go" 'response\.InternalError\(c, err\.Error\(\)\)'
require_text "backend/internal/handler/category.go" 'failed to list categories'
require_absent_text "backend/internal/handler/template.go" 'response\.InternalError\(c, err\.Error\(\)\)'
require_text "backend/internal/handler/template.go" 'failed to list templates'
require_absent_text "backend/internal/handler/budget.go" 'response\.InternalError\(c, err\.Error\(\)\)'
require_text "backend/internal/handler/budget.go" 'failed to list budgets'
require_absent_text "backend/internal/handler/reminder.go" 'response\.InternalError\(c, err\.Error\(\)\)'
require_text "backend/internal/handler/reminder.go" 'failed to list reminders'
require_absent_text "backend/internal/handler/notification.go" 'response\.InternalError\(c, err\.Error\(\)\)'
require_absent_text "backend/internal/handler/notification.go" 'existing, _'
require_text "backend/internal/handler/notification.go" 'failed to load notification settings'
require_absent_text "backend/internal/handler/family.go" 'response\.InternalError\(c, err\.Error\(\)\)'
require_absent_text "backend/internal/handler/family.go" 'response\.Error\(c, .*err\.Error\(\)\)'
require_text "backend/internal/handler/family.go" 'failed to list family members'
require_absent_text "backend/internal/handler/tag.go" 'c\.JSON\([^[:space:]]*http\.StatusInternalServerError'
require_text "backend/internal/handler/tag.go" 'failed to list tags'
require_absent_text "backend/internal/handler/api_token.go" 'c\.JSON\([^[:space:]]*http\.StatusInternalServerError'
require_text "backend/internal/handler/api_token.go" 'failed to list tokens'
require_text "backend/internal/handler/api_token.go" 'response\.Success'
require_absent_text "backend/internal/service/statistics.go" 'prevSum, _'
require_absent_text "backend/internal/service/statistics.go" 'categories, _'
require_absent_text "backend/internal/service/notification.go" 'existing, _'
require_absent_text "backend/internal/service/notification.go" 'Message: err\.Error\(\)'
require_absent_text "backend/internal/service/notification.go" '邮箱: "\+err\.Error\(\)'
require_text "backend/internal/service/notification.go" '通知发送失败，请检查通知地址或网络'
require_text "backend/internal/service/notification.go" '邮件发送失败，请检查邮箱配置或网络'
require_text "backend/internal/service/notification.go" 'gorm\.ErrRecordNotFound'
require_absent_text "backend/internal/service/tag.go" 'existing, _'
require_text "backend/internal/service/tag.go" 'gorm\.ErrRecordNotFound'
require_absent_text "backend/internal/service/backup.go" 'notificationSettings, _'
require_absent_text "backend/internal/middleware/rate_limiter.go" 'strings\.HasPrefix\(path, "/uploads/"\)[[:space:]]*\|\|'
require_text "backend/internal/middleware/rate_limiter.go" 'isPublicUploadPath'
require_absent_text "web/src/views/SettingsView.vue" '至少6位|至少6 位|至少 6 位'
require_absent_text "web/src/views/SettingsView.vue" 'v-model="notificationForm\.(dingtalk_secret|smtp_password|webhook_secret)"[^>]*type="text"'
require_absent_text "web/src/views/SettingsView.vue" 'notificationApi\.updateSettings\(notificationForm\.value\)'
require_absent_text "mobile/lib/features/notifications/data/notification_repository.dart" "^[[:space:]]*'(dingtalk_secret|webhook_secret)': (dingtalkSecret|webhookSecret),"
require_absent_text "mobile/lib/features/ai/data/ai_report_repository.dart" "^[[:space:]]*'api_key': apiKey,"
require_absent_text "web/src/views/AIView.vue" 'api_key: providerForm\.api_key\.trim\(\)'
require_absent_text "web/src/utils/request.ts" 'error\.message'
require_text "web/src/utils/request.ts" "error\\.response \\? '请求失败' : '网络连接失败'"
require_absent_text "mobile/lib/core/network/api_client.dart" 'message: error\.message'
require_text "mobile/lib/core/network/api_client.dart" "message: error\\.response == null \\? '网络连接失败' : '请求失败'"
require_text "mobile/lib/core/config/server_config_service.dart" '远程服务器必须使用 HTTPS'
require_absent_text "backend/internal/service/auth.go" 'password must be at least 6 characters'
require_absent_text "backend/internal/handler/auth.go" 'invalid request: "\+err\.Error\(\)'
require_absent_text "backend/internal/handler/setup.go" 'invalid request: "\+err\.Error\(\)'
require_text "scripts/check-release-artifact-files.sh" 'REQUIRE_CHECKSUM_SIDECARS:-1'
require_text "scripts/check-release-artifact-files.sh" 'VERIFY_ARTIFACT_SIGNATURES:-0'
require_text "scripts/check-release-artifact-files.sh" 'Missing \$label checksum sidecar'
require_text "scripts/check-release-artifact-files.sh" 'check_artifact_structure'
require_text "scripts/check-release-artifact-files.sh" 'verify_artifact_signature'
require_text "scripts/check-release-artifact-files.sh" 'signature checks passed'
require_text "scripts/check-release-artifact-files.sh" '\^AndroidManifest\\.xml\$'
require_text "scripts/check-release-artifact-files.sh" '\^BundleConfig\\.pb\$'
require_text "scripts/check-release-artifact-files.sh" '\^Payload/\[\^/\]\+\\.app/Info\\.plist\$'
require_text ".github/workflows/android.yml" "Verify Android release signatures"
require_text ".github/workflows/android.yml" "APKSIGNER.*verify --verbose --print-certs"
require_text ".github/workflows/android.yml" "jarsigner -verify -strict -certs"
require_text ".github/workflows/ios.yml" "Verify iOS IPA signature"
require_text ".github/workflows/ios.yml" "CFBundleIdentifier"
require_text ".github/workflows/ios.yml" "codesign --verify --deep --strict"
require_text ".github/workflows/release.yml" "verify-android-artifact"
require_text ".github/workflows/release.yml" "verify-ios-artifact"
require_text ".github/workflows/release.yml" "runs-on: macos-latest"
require_text ".github/workflows/release.yml" "actions/setup-java@v4"
require_text ".github/workflows/release.yml" "actions: read"
require_text ".github/workflows/release.yml" "REQUIRE_ANDROID_ARTIFACTS=0"
require_text ".github/workflows/release.yml" "REQUIRE_IOS_ARTIFACT=0"
require_text ".github/workflows/release.yml" "VERIFY_ARTIFACT_SIGNATURES=1"
require_text "scripts/check-docker-release-evidence.sh" 'pick_port'
require_text "scripts/check-docker-release-evidence.sh" 'Image healthcheck: healthy'
require_text "scripts/check-docker-release-evidence.sh" 'Persistent paths: ledger\.db, uploads, backups'
require_text "scripts/check-docker-release-evidence.sh" 'mktemp /tmp/personal-ledger-docker-manifest'
require_text "scripts/check-docker-release-evidence.sh" 'DOCKER_RELEASE_IMAGE is required when STRICT_DOCKER_RELEASE_EVIDENCE=1'
require_text "scripts/check-docker-release-evidence.sh" 'RUN_DOCKER_RELEASE_SMOKE=1 is required when STRICT_DOCKER_RELEASE_EVIDENCE=1'
require_text "scripts/check-final-release-gates.sh" 'SKIP_EXTERNAL_RELEASE_EVIDENCE cannot be used with STRICT_FINAL_RELEASE=1'
require_text "scripts/check-final-release-gates.sh" 'STRICT_FINAL_RELEASE:-0.*!= "1"'
require_text "scripts/check-final-release-gates.sh" 'Final release structural checks passed'
require_text "scripts/check-final-release-gates.sh" 'Strict final release gate checks passed'
require_text "scripts/check-final-release-gates.sh" 'Working tree must be clean before strict final release'
require_text "scripts/check-final-release-gates.sh" 'clean working tree'
require_text "scripts/check-final-release-gates.sh" 'RUN_DOCKER_RELEASE_SMOKE=1'
require_text "scripts/check-final-release-gates.sh" 'env REQUIRE_IOS_ARTIFACT=1 VERIFY_ARTIFACT_SIGNATURES=1 "\$ROOT_DIR/scripts/check-release-artifact-files\.sh"'
require_text "scripts/check-final-release-gates.sh" 'REQUIRE_ANDROID_DEVICE=1'
require_text "scripts/check-mobile-device-qa-preflight.sh" 'REQUIRE_ANDROID_DEVICE:-0'
require_text "scripts/check-mobile-device-qa-preflight.sh" 'No Android device or emulator detected'
require_text "scripts/check-mobile-device-qa-preflight.sh" 'RUN_ANDROID_E2E'
require_text "scripts/check-final-release-runbook.sh" '\^## 4\\. Mobile Device QA'
require_text "scripts/check-final-release-runbook.sh" 'REQUIRE_PHYSICAL_IOS=1 REQUIRE_ANDROID_DEVICE=1'
require_text "scripts/check-final-release-runbook.sh" 'RUN_ANDROID_E2E=1'
require_text "docs/quality/mobile-device-qa-checklist-2026-05-27.md" 'REQUIRE_ANDROID_DEVICE=1'
require_text "docs/quality/mobile-device-qa-checklist-2026-05-27.md" 'Android E2E'
require_text "docs/quality/mobile-device-qa-checklist-2026-05-27.md" 'USB iPhone and Android device/emulator'
require_text "docs/quality/mobile-device-qa-checklist-2026-05-27.md" 'Android status/navigation bars'
require_text "docs/quality/mobile-device-qa-checklist-2026-05-27.md" 'on iOS and Android'
require_text "docs/quality/production-readiness-2026-05-27.md" 'REQUIRE_PHYSICAL_IOS=1 REQUIRE_ANDROID_DEVICE=1'
require_text "docs/quality/production-readiness-2026-05-27.md" 'iOS/Android device validation'
require_text "docs/quality/production-readiness-2026-05-27.md" 'USB iPhone and Android release-device evidence remain missing'
require_text "docs/quality/release-artifact-evidence-2026-05-27.md" 'iOS/Android device QA'
require_text "docs/quality/release-artifact-evidence-2026-05-27.md" 'RELEASE_ARTIFACT_DIR=artifacts RELEASE_VERSION=<version> REQUIRE_IOS_ARTIFACT=1 VERIFY_ARTIFACT_SIGNATURES=1'
require_text "docs/quality/release-artifact-evidence-2026-05-27.md" 'iOS signatures on macOS'
require_text "docs/quality/release-notes-candidate-2026-05-27.md" 'iOS and Android device validation'
require_text "docs/quality/local-release-rehearsal-2026-05-27.md" 'iOS/Android device QA'
require_text "docs/quality/mobile-platform-qa-2026-05-27.md" 'iOS/Android release-device QA'
require_text "docs/quality/mobile-platform-qa-2026-05-27.md" 'Android release-device evidence'
require_text "docs/quality/mobile-premium-visual-review-2026-05-27.md" 'final iOS/Android release-device QA'
require_text "docs/quality/mobile-premium-visual-review-2026-05-27.md" 'USB-connected iPhone and an Android device/emulator'
require_text "docs/quality/local-release-rehearsal-2026-05-27.md" 'release-image smoke'
require_text "scripts/check-final-release-runbook.sh" 'VERIFY_ARTIFACT_SIGNATURES=1'
require_text "docs/quality/final-release-runbook-2026-05-27.md" 'VERIFY_ARTIFACT_SIGNATURES=1'
require_text "docs/quality/final-release-runbook-2026-05-27.md" 'clean `git status --short`'
require_text "docs/quality/final-release-runbook-2026-05-27.md" 'DOCKER_RELEASE_IMAGE=ghcr.io/<owner>/<repo>:X.Y.Z'
require_text "docs/quality/final-release-runbook-2026-05-27.md" 'release-image compose smoke'
require_text "docs/quality/final-release-runbook-2026-05-27.md" '^## 4\. Mobile Device QA'
require_text "docs/quality/final-release-runbook-2026-05-27.md" 'Android device not detected'
require_text "docs/quality/release-artifact-evidence-2026-05-27.md" 'VERIFY_ARTIFACT_SIGNATURES=1'
require_text "docs/quality/docker-release-evidence-2026-05-27.md" 'STRICT_DOCKER_RELEASE_EVIDENCE=1'
require_text "docs/quality/docker-release-evidence-2026-05-27.md" 'RUN_DOCKER_RELEASE_SMOKE=1'
require_text "docs/android-release-signing.md" 'VERIFY_ARTIFACT_SIGNATURES=1'
require_text "docs/ios-release-signing.md" 'VERIFY_ARTIFACT_SIGNATURES=1'
require_text "docs/quality/production-readiness-2026-05-27.md" 'VERIFY_ARTIFACT_SIGNATURES=1'
require_text "docs/quality/release-notes-candidate-2026-05-27.md" 'VERIFY_ARTIFACT_SIGNATURES=1'
if ! perl -0ne 'exit 1 if /ShouldBindJSON\(&req\); err != nil \{\n\t\tresponse\.BadRequest\(c, err\.Error\(\)\)/' "$ROOT_DIR"/backend/internal/handler/*.go; then
  echo "Unexpected bind error detail returned from handler" >&2
  exit 1
fi

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
