# Release Change Inventory - 2026-05-27

## Conclusion

This document records the intended release change set before staging, commit, tag, or public distribution. The current worktree is large, but the changed paths below are categorized into the release scope for the family + AI + premium mobile + release readiness objective.

Current status: path inventory populated from `git status --porcelain=v1` on 2026-05-27. Final staging should still be split into reviewable commit groups.

## Scope Summary

| Area | Status | Notes |
| --- | --- | --- |
| Family accounting backend/API | REVIEWED | Family member model, service, handler, transaction member fields, summary API |
| OpenAI-compatible AI analysis | REVIEWED | Provider config, protected API keys, report generation, web/mobile report views |
| Premium mobile UI | REVIEWED | Design tokens, motion widgets, Home, Quick Transaction, Family Hub, AI Reports |
| Web family/AI views | REVIEWED | Family and AI pages plus navigation/settings integration |
| Backup and recovery | REVIEWED | Backup scope, AI reports, family members, operator drill evidence |
| Release and QA gates | REVIEWED | Android/iOS workflows, artifact checks, final gates, release notes, mobile QA |
| Generated or local-only files | REVIEWED | No generated build artifacts or signing material are part of the intended release scope |

## Required Review Rules

| Rule | Required Result | Status |
| --- | --- | --- |
| No credentials | No `.env`, private keys, keystores, certificates, tokens, local databases, or signing material are staged | REVIEWED |
| No generated output | No `build/`, `dist/`, `.dart_tool/`, `.gradle/`, `node_modules/`, APK/AAB/IPA, or local cache output is staged | REVIEWED |
| pnpm-only web | No `package-lock.json`, `yarn.lock`, or `bun.lockb` exists under `web/` | REVIEWED |
| Intentional changed paths | Every changed path in `git status --short` is categorized in this inventory before release | REVIEWED |
| Reviewable commit groups | Changes can be split into family, AI, mobile premium, web UI, release QA, and docs/checklist groups | REVIEWED |

## Intended Change Groups

### Family Accounting

Backend family/accounting domain:

```text
backend/internal/database/database.go
backend/internal/handler/family.go
backend/internal/handler/family_test.go
backend/internal/handler/handler.go
backend/internal/model/family_member.go
backend/internal/model/models.go
backend/internal/repository/family_member.go
backend/internal/repository/repository.go
backend/internal/repository/transaction.go
backend/internal/service/family_member.go
backend/internal/service/family_member_test.go
backend/internal/service/service.go
backend/internal/service/transaction.go
backend/internal/service/transaction_test.go
```

Mobile family support:

```text
mobile/lib/features/family/
mobile/test/family_widget_test.dart
```

Family architecture:

```text
docs/architecture/family-mode.md
```

### AI Analysis

Backend AI provider/report domain:

```text
backend/internal/handler/ai.go
backend/internal/handler/ai_test.go
backend/internal/model/ai.go
backend/internal/repository/ai_provider.go
backend/internal/repository/ai_report.go
backend/internal/service/ai_openai_client.go
backend/internal/service/ai_provider.go
backend/internal/service/ai_provider_test.go
backend/internal/service/ai_report.go
backend/internal/service/ai_report_test.go
backend/internal/service/ai_secret.go
```

Mobile AI support:

```text
mobile/lib/features/ai/
mobile/lib/features/ai/presentation/ai_reports_page.dart
mobile/test/ai_reports_widget_test.dart
```

Web AI support:

```text
web/src/api/ai.ts
web/src/views/AIView.vue
```

AI architecture:

```text
docs/architecture/ai-analysis.md
```

### Premium Mobile UI

Flutter premium foundation, screens, and tests:

```text
mobile/integration_test/premium_screens_smoke_test.dart
mobile/lib/app/router/app_route_paths.dart
mobile/lib/app/router/app_router.dart
mobile/lib/app/theme/app_theme.dart
mobile/lib/app/theme/motion_tokens.dart
mobile/lib/app/widgets/animated_money_text.dart
mobile/lib/app/widgets/premium_surface.dart
mobile/lib/app/widgets/pressable_scale.dart
mobile/lib/app/widgets/staggered_entrance.dart
mobile/lib/core/network/auth_interceptor.dart
mobile/lib/features/home/data/home_repository.dart
mobile/lib/features/home/presentation/home_page.dart
mobile/lib/features/home/presentation/widgets/
mobile/lib/features/main/presentation/main_shell_page.dart
mobile/lib/features/profile/presentation/profile_page.dart
mobile/lib/features/transactions/data/transaction_models.dart
mobile/lib/features/transactions/presentation/quick_transaction_page.dart
mobile/test/animated_money_text_test.dart
mobile/test/auth_interceptor_test.dart
mobile/test/home_widget_test.dart
mobile/test/main_shell_widget_test.dart
mobile/test/premium_accessibility_test.dart
mobile/test/premium_motion_widgets_test.dart
mobile/test/profile_widget_test.dart
mobile/test/quick_transaction_form_validation_test.dart
scripts/verify-mobile-e2e.sh
```

Premium design and implementation plans:

```text
docs/design/
docs/superpowers/plans/2026-05-27-mobile-platform-qa-release-readiness.md
docs/superpowers/plans/2026-05-27-mobile-premium-ai-reports.md
docs/superpowers/plans/2026-05-27-mobile-premium-family-hub.md
docs/superpowers/plans/2026-05-27-mobile-premium-foundation-home.md
docs/superpowers/plans/2026-05-27-mobile-premium-quick-transaction.md
```

### Web UI

Vue family/AI integration and transaction member selector:

```text
web/src/api/export.ts
web/package.json
web/pnpm-lock.yaml
web/src/api/family.ts
web/src/api/transaction.ts
web/src/components/TransactionDialog.vue
web/src/router/index.ts
web/src/views/FamilyView.vue
web/src/views/HomeView.vue
web/src/views/LayoutView.vue
web/src/views/SettingsView.vue
```

### Backup, Release, And QA

Backup scope, restore tests, and AI/family backup coverage:

```text
backend/internal/handler/backup.go
backend/internal/handler/backup_restore_test.go
backend/internal/service/backup.go
backend/internal/service/backup_scheduler.go
backend/internal/service/backup_scheduler_test.go
backend/internal/service/backup_scope_test.go
backend/internal/service/backup_test.go
docs/architecture/backup-scope.md
```

Release workflows, signing docs, quality evidence, and gate scripts:

```text
.github/workflows/android.yml
.github/workflows/ios.yml
.github/workflows/release.yml
.env.example
.gitignore
Dockerfile
README.md
backend/cmd/server/main.go
backend/cmd/server/main_test.go
backend/internal/config/config.go
backend/internal/handler/upload.go
backend/internal/handler/upload_test.go
backend/internal/middleware/middleware.go
backend/internal/middleware/middleware_test.go
backend/internal/repository/category.go
backend/internal/repository/api_token.go
backend/internal/repository/user.go
backend/internal/service/ai_report.go
backend/internal/service/ai_report_test.go
backend/internal/service/api_token.go
backend/internal/service/api_token_test.go
backend/internal/service/auth.go
backend/internal/service/auth_test.go
backend/internal/service/upload.go
config.example.yaml
docker-compose.yml
docs/android-release-signing.md
docs/ios-release-signing.md
docs/quality/
docs/quality/final-release-runbook-2026-05-27.md
docs/quality/docker-release-evidence-2026-05-27.md
docs/quality/local-release-rehearsal-2026-05-27.md
docs/quality/release-change-inventory-2026-05-27.md
docs/superpowers/plans/2026-05-27-family-ai-mobile-modernization.md
scripts/check-backup-operator-drill.sh
scripts/check-backup-operator-drill-local.sh
scripts/check-backup-restore-rehearsal.sh
scripts/check-docker-compose-local-smoke.sh
scripts/check-docker-local-smoke.sh
scripts/check-docker-release-evidence.sh
scripts/check-docker-release-preflight.sh
scripts/check-final-release-gates.sh
scripts/check-final-release-runbook.sh
scripts/check-mobile-device-qa-preflight.sh
scripts/check-production-readiness.sh
scripts/check-public-git-safety.sh
scripts/check-release-artifact-files.sh
scripts/check-release-artifacts-preflight.sh
scripts/check-release-change-inventory.sh
scripts/check-release-notes-candidate.sh
```

## Excluded From Release

No local-only generated path is intentionally part of the release. The release scope checker rejects the following classes if they appear in `git status`:

```text
.env
key.properties
local.properties
google-services.json
GoogleService-Info.plist
*.db
*.sqlite
*.apk
*.ipa
*.aab
*.jks
*.keystore
*.p12
*.pem
*.key
*.crt
node_modules/
.dart_tool/
.gradle/
build/
dist/
```

## Strict Check

Run:

```bash
STRICT_RELEASE_SCOPE=1 ./scripts/check-release-change-inventory.sh
```

Strict mode should pass only after:

- this document has no unresolved inventory placeholders;
- every path from `git status --short` is mentioned here;
- no forbidden generated or secret-like files appear in the working tree status.
