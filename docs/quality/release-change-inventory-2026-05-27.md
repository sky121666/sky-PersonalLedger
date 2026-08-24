# Release Change Inventory - 2026-05-27

## Conclusion

This document records the intended release change set before staging, commit, tag, or public distribution. The changed paths below are categorized into the release scope for the family, AI, client consistency, data protection, and release-readiness objective.

Current status: the original 2026-05-27 inventory and the 2026-08-24 unified-hardening delta have both been reviewed. The unified-hardening implementation is committed as `2daa3a1`; the v1.0.9 publication-preparation delta below contains only release gates, truthful documentation, and isolated screenshots. The immutable-tag recovery delta records the protected, exact-commit path used when a tag workflow cannot start any job; it does not change product source or version content.

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
| Explicit QA evidence review | `output/` and `mobile/QA/{design,reports,screenshots}/` are blocked from staging unless `ALLOW_REVIEW_ARTIFACTS=1` is deliberately set after review | REVIEWED |
| Staged size ceiling | No staged file exceeds 5 MiB unless the safety rule is deliberately changed and reviewed | REVIEWED |
| pnpm-only web | No `package-lock.json`, `yarn.lock`, or `bun.lockb` exists under `web/` | REVIEWED |
| Intentional changed paths | Every changed path in `git status --short` is categorized in this inventory before release | REVIEWED |
| Coherent commit scope | The unified hardening delta contains only client consistency, data protection, release governance, validation, and their documentation/tests | REVIEWED |

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
mobile/lib/features/ai/data/ai_report_repository.dart
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
mobile/integration_test/app_real_backend_e2e_test.dart
mobile/integration_test/app_smoke_test.dart
mobile/integration_test/premium_screens_smoke_test.dart
mobile/lib/app/router/app_route_paths.dart
mobile/lib/app/router/app_router.dart
mobile/lib/app/theme/app_theme.dart
mobile/lib/app/theme/motion_tokens.dart
mobile/lib/app/widgets/animated_money_text.dart
mobile/lib/app/widgets/premium_surface.dart
mobile/lib/app/widgets/pressable_scale.dart
mobile/lib/app/widgets/staggered_entrance.dart
mobile/lib/core/config/server_config_service.dart
mobile/lib/core/network/auth_interceptor.dart
mobile/lib/features/attachments/data/attachment_repository.dart
mobile/lib/features/auth/presentation/setup_password_page.dart
mobile/lib/features/home/data/home_repository.dart
mobile/lib/features/home/presentation/home_page.dart
mobile/lib/features/home/presentation/widgets/
mobile/lib/features/main/presentation/main_shell_page.dart
mobile/lib/features/notifications/data/notification_repository.dart
mobile/lib/features/notifications/presentation/notification_settings_page.dart
mobile/lib/features/profile/presentation/profile_page.dart
mobile/lib/features/transactions/data/transaction_models.dart
mobile/lib/features/transactions/presentation/quick_transaction_page.dart
mobile/lib/features/data_management/data/data_management_repository.dart
mobile/test/animated_money_text_test.dart
mobile/test/auth_flow_widget_test.dart
mobile/test/auth_interceptor_test.dart
mobile/test/core_response_parsing_test.dart
mobile/test/data_management_repository_test.dart
mobile/test/home_widget_test.dart
mobile/test/lending_widget_test.dart
mobile/test/main_shell_widget_test.dart
mobile/test/notification_widget_test.dart
mobile/test/premium_accessibility_test.dart
mobile/test/premium_motion_widgets_test.dart
mobile/test/profile_widget_test.dart
mobile/test/quick_transaction_form_validation_test.dart
mobile/test/reminder_widget_test.dart
scripts/verify-mobile-e2e.sh
```

Current premium mobile accessibility, stability, and widget-test audit delta:

```text
mobile/lib/app/widgets/adaptive_page_container.dart
mobile/lib/app/widgets/animated_money_text.dart
mobile/lib/app/widgets/app_state_views.dart
mobile/lib/app/widgets/auth_flow_shell.dart
mobile/lib/app/widgets/finance_dashboard_widgets.dart
mobile/lib/app/widgets/ledger_icon.dart
mobile/lib/app/widgets/premium_surface.dart
mobile/lib/app/widgets/pressable_scale.dart
mobile/lib/features/account_logs/presentation/account_log_page.dart
mobile/lib/features/accounts/presentation/accounts_page.dart
mobile/lib/features/ai/presentation/ai_reports_page.dart
mobile/lib/features/api_tokens/presentation/api_token_page.dart
mobile/lib/features/attachments/presentation/attachment_picker_field.dart
mobile/lib/features/auth/presentation/login_page.dart
mobile/lib/features/auth/presentation/setup_password_page.dart
mobile/lib/features/bootstrap/presentation/bootstrap_page.dart
mobile/lib/features/budgets/presentation/budget_page.dart
mobile/lib/features/categories/presentation/categories_page.dart
mobile/lib/features/data_management/presentation/data_management_page.dart
mobile/lib/features/family/presentation/family_page.dart
mobile/lib/features/home/presentation/home_page.dart
mobile/lib/features/home/presentation/widgets/home_dashboard_widgets.dart
mobile/lib/features/lendings/presentation/lending_page.dart
mobile/lib/features/main/presentation/main_shell_page.dart
mobile/lib/features/notifications/presentation/notification_settings_page.dart
mobile/lib/features/profile/presentation/profile_page.dart
mobile/lib/features/profile/presentation/profile_settings_page.dart
mobile/lib/features/reminders/presentation/reminder_page.dart
mobile/lib/features/reports/presentation/yearly_report_page.dart
mobile/lib/features/security/presentation/security_settings_page.dart
mobile/lib/features/server_config/presentation/server_config_page.dart
mobile/lib/features/statistics/presentation/mobile_statistics_page.dart
mobile/lib/features/tags/presentation/tag_page.dart
mobile/lib/features/templates/presentation/template_page.dart
mobile/lib/features/transactions/presentation/quick_transaction_page.dart
mobile/lib/features/transactions/presentation/transaction_details_page.dart
mobile/test/account_log_widget_test.dart
mobile/test/accounts_widget_test.dart
mobile/test/adaptive_page_container_test.dart
mobile/test/ai_reports_widget_test.dart
mobile/test/animated_money_text_test.dart
mobile/test/api_token_widget_test.dart
mobile/test/app_state_views_test.dart
mobile/test/attachment_picker_field_test.dart
mobile/test/auth_flow_widget_test.dart
mobile/test/bootstrap_widget_test.dart
mobile/test/budget_widget_test.dart
mobile/test/category_widget_test.dart
mobile/test/data_management_widget_test.dart
mobile/test/family_widget_test.dart
mobile/test/finance_dashboard_widgets_test.dart
mobile/test/home_widget_test.dart
mobile/test/icon_button_accessibility_contract_test.dart
mobile/test/ledger_icon_widget_test.dart
mobile/test/lending_widget_test.dart
mobile/test/main_shell_widget_test.dart
mobile/test/notification_widget_test.dart
mobile/test/premium_accessibility_test.dart
mobile/test/premium_motion_widgets_test.dart
mobile/test/profile_settings_widget_test.dart
mobile/test/profile_widget_test.dart
mobile/test/quick_transaction_form_validation_test.dart
mobile/test/reminder_widget_test.dart
mobile/test/security_settings_widget_test.dart
mobile/test/server_config_widget_test.dart
mobile/test/statistics_widget_test.dart
mobile/test/tag_widget_test.dart
mobile/test/template_widget_test.dart
mobile/test/transaction_details_widget_test.dart
mobile/test/yearly_report_widget_test.dart
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
web/src/api/notification.ts
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
backend/internal/handler/account.go
backend/internal/handler/account_log.go
backend/internal/handler/account_test.go
backend/internal/handler/api_token.go
backend/internal/handler/auth.go
backend/internal/handler/auth_test.go
backend/internal/handler/attachment.go
backend/internal/handler/attachment_test.go
backend/internal/handler/budget.go
backend/internal/handler/category.go
backend/internal/handler/error_response.go
backend/internal/handler/export.go
backend/internal/handler/lending.go
backend/internal/handler/lending_test.go
backend/internal/handler/notification.go
backend/internal/handler/query_error_response_test.go
backend/internal/handler/reminder.go
backend/internal/handler/setup.go
backend/internal/handler/setup_test.go
backend/internal/handler/statistics.go
backend/internal/handler/statistics_test.go
backend/internal/handler/system.go
backend/internal/handler/tag.go
backend/internal/handler/template.go
backend/internal/handler/transaction.go
backend/internal/handler/transaction_test.go
backend/internal/handler/upload.go
backend/internal/handler/upload_test.go
backend/internal/middleware/middleware.go
backend/internal/middleware/middleware_test.go
backend/internal/middleware/rate_limiter.go
backend/internal/middleware/rate_limiter_test.go
backend/internal/repository/category.go
backend/internal/repository/api_token.go
backend/internal/repository/refresh_token.go
backend/internal/repository/user.go
backend/internal/service/ai_report.go
backend/internal/service/ai_report_test.go
backend/internal/service/api_token.go
backend/internal/service/api_token_test.go
backend/internal/service/auth.go
backend/internal/service/auth_test.go
backend/internal/service/health.go
backend/internal/service/health_test.go
backend/internal/service/lending.go
backend/internal/service/lending_test.go
backend/internal/service/notification.go
backend/internal/service/notification_test.go
backend/internal/service/statistics.go
backend/internal/service/tag.go
backend/internal/service/upload.go
backend/internal/service/upload_test.go
backend/pkg/jwt/jwt.go
backend/pkg/jwt/jwt_test.go
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

### Current Completion And Quality-Gate Delta (2026-08-01)

The following paths were added to the review inventory after the original May snapshot. They cover the security, accounting, import, mobile design, Web, database-matrix, and release-gate completion work. Inventory coverage records review scope only; it does not authorize automatic staging or imply that local QA evidence must ship in a release.

```text
.dockerignore
.github/workflows/backend-database.yml
.github/workflows/docker.yml
.github/workflows/macos.yml
.github/workflows/mobile-e2e.yml
.github/workflows/mobile-quality.yml
.github/workflows/public-git-safety.yml
.github/workflows/web.yml
.github/workflows/windows.yml
backend/go.mod
backend/go.sum
backend/internal/authz/
backend/internal/config/config_test.go
backend/internal/database/database_integration_test.go
backend/internal/database/database_logging_test.go
backend/internal/database/database_test.go
backend/internal/handler/account_log_test.go
backend/internal/handler/backup_create_test.go
backend/internal/handler/export_test.go
backend/internal/handler/route_contract_test.go
backend/internal/handler/template_test.go
backend/internal/handler/transaction_export_date_test.go
backend/internal/handler/transaction_import.go
backend/internal/handler/transaction_import_test.go
backend/internal/middleware/audit_log.go
backend/internal/middleware/audit_log_test.go
backend/internal/middleware/setup_access.go
backend/internal/middleware/setup_access_test.go
backend/internal/model/account_types.go
backend/internal/model/api_token.go
backend/internal/model/transaction_import.go
backend/internal/repository/account.go
backend/internal/repository/account_log.go
backend/internal/repository/account_log_test.go
backend/internal/repository/budget.go
backend/internal/repository/notification.go
backend/internal/repository/notification_log.go
backend/internal/repository/reminder.go
backend/internal/repository/tag.go
backend/internal/repository/tag_test.go
backend/internal/repository/template.go
backend/internal/service/account.go
backend/internal/service/account_log.go
backend/internal/service/account_log_test.go
backend/internal/service/account_test.go
backend/internal/service/ai_report_scheduler_test.go
backend/internal/service/audit_regression_test.go
backend/internal/service/backup_attachments.go
backend/internal/service/backup_guard.go
backend/internal/service/backup_guard_test.go
backend/internal/service/backup_integrity_test.go
backend/internal/service/backup_json.go
backend/internal/service/backup_notification.go
backend/internal/service/backup_references.go
backend/internal/service/backup_security_limits_test.go
backend/internal/service/budget.go
backend/internal/service/budget_test.go
backend/internal/service/category.go
backend/internal/service/category_test.go
backend/internal/service/export.go
backend/internal/service/export_test.go
backend/internal/service/local_date.go
backend/internal/service/local_date_test.go
backend/internal/service/money_precision.go
backend/internal/service/money_precision_integration_test.go
backend/internal/service/notification_scheduler.go
backend/internal/service/notification_scheduler_test.go
backend/internal/service/notification_secret.go
backend/internal/service/optional.go
backend/internal/service/outbound_network.go
backend/internal/service/outbound_network_test.go
backend/internal/service/reminder.go
backend/internal/service/reminder_test.go
backend/internal/service/statistics_test.go
backend/internal/service/system.go
backend/internal/service/system_test.go
backend/internal/service/tag_test.go
backend/internal/service/template.go
backend/internal/service/template_test.go
backend/internal/service/transaction_import.go
backend/internal/service/transaction_import_test.go
backend/internal/service/upload_gc.go
backend/internal/service/upload_references.go
backend/internal/service/upload_validation.go
design-qa.md
docker-compose.debug.yml
docs/design/corgi-ledger-design-system-p0-2026-06-18.md
docs/design/corgi-ledger-friendly-premium-v3-target-2026-06-17.md
docs/design/corgi-ledger-interactive-v4-motion-plan-2026-06-17.md
docs/design/corgi-ledger-premium-v2-target-2026-06-17.md
docs/design/corgi-ledger-ui-target-2026-06-17.md
docs/design/mobile-apple-minimal-final-qa-2026-08-03.md
docs/quality/production-readiness-2026-05-27.md
mobile/QA/design/
mobile/QA/reports/quality_audit_20260608_020014.json
mobile/QA/reports/quality_audit_20260608_020014.md
mobile/QA/reports/quality_cleanliness_20260608_020014.json
mobile/QA/reports/quality_scores_20260608_020014.json
mobile/QA/reports/route_quality_check_20260608_020014.json
mobile/QA/reports/route_quality_check_20260608_020014.md
mobile/QA/screenshots/20260607-home.png
mobile/QA/screenshots/20260607-lendings-real.png
mobile/QA/screenshots/20260607-lendings.png
mobile/QA/screenshots/20260607-profile-daily-expanded.png
mobile/QA/screenshots/20260607-profile.png
mobile/QA/screenshots/20260607-profile2.png
mobile/QA/screenshots/20260607-quick-transaction.png
mobile/QA/screenshots/20260607-statistics.png
mobile/QA/screenshots/20260607-transactions.png
mobile/QA/screenshots/after/
mobile/QA/screenshots/android/android-emulator-install-launch-20260608.png
mobile/QA/screenshots/android/android-emulator-local-address-install-20260608.png
mobile/QA/screenshots/android/android-emulator-runtime-server-20260608.png
mobile/QA/screenshots/android/android-perfect-polish-20260607-140352.png
mobile/QA/screenshots/android/android-period-family-year-20260615.png
mobile/QA/screenshots/android/android-period-home-history-20260615.png
mobile/QA/screenshots/android/android-period-home-month-20260615.png
mobile/QA/screenshots/android/android-period-home-year-20260615.png
mobile/QA/screenshots/android/android-period-statistics-year-20260615.png
mobile/QA/screenshots/android/android-plus-polish-20260607-140411.png
mobile/QA/screenshots/android/android-smart-quick-drafts-20260615.png
mobile/QA/screenshots/android/android-smart-quick-enabled-20260615.png
mobile/QA/screenshots/android/android-smart-quick-ledger-candidate-20260615.png
mobile/QA/screenshots/android/android-smart-quick-ledger-confirmed-20260615.png
mobile/QA/screenshots/android/android-smart-quick-ledger-notification-access-20260615.png
mobile/QA/screenshots/android/p1-corgi-related-20260618/
mobile/QA/screenshots/android/real-phone-20260616-profile/
mobile/QA/screenshots/android/real-phone-20260616/
mobile/QA/screenshots/android/ui-redesign-20260615/
mobile/QA/screenshots/android/ui95-final-20260615/
mobile/QA/screenshots/android/ui95-redesign-20260615/
mobile/QA/screenshots/android/v4-p0-20260617/
mobile/QA/screenshots/current/home-phone.png
mobile/QA/screenshots/current/ios-data-management-batch1.png
mobile/QA/screenshots/current/ios-feature-center-clean-final.png
mobile/QA/screenshots/current/ios-feature-center-cleaner-final.png
mobile/QA/screenshots/current/ios-feature-center-compact-current.jpg
mobile/QA/screenshots/current/ios-feature-center-current.jpg
mobile/QA/screenshots/current/ios-feature-center-final-current.png
mobile/QA/screenshots/current/ios-home-current.png
mobile/QA/screenshots/current/ios-lending-final-current.png
mobile/QA/screenshots/current/ios-statistics-current.jpg
mobile/QA/screenshots/current/ios-transactions-current.jpg
mobile/QA/screenshots/current/ios-transactions-filtered-current.jpg
mobile/QA/screenshots/current/ios-transactions-final-current.png
mobile/QA/screenshots/current/lending-phone.png
mobile/QA/screenshots/ios/ios-after-smoke-20260607-130309.png
mobile/QA/screenshots/ios/ios-home-20260607-130120.png
mobile/QA/screenshots/ios/ios-installed-launch-20260607-130455.png
mobile/QA/screenshots/ios/ios-perfect-final-home-20260607-134810.png
mobile/QA/screenshots/ios/ios-perfect-polish-20260607-140136.png
mobile/QA/screenshots/ios/ios-polish-final-clean-home-20260607-133118.png
mobile/QA/screenshots/ios/ios-polish-final-home-20260607-132950.png
mobile/QA/screenshots/ios/ios-polish-home-20260607-132654.png
mobile/QA/screenshots/ios/ios-polish-transactions-20260607-132841.png
mobile/QA/screenshots/ios/ios-profile-theme-maincolor-20260607-1421.jpg
mobile/QA/screenshots/ios/ios-relaunch-20260607-130345.png
mobile/QA/screenshots/ios/ui95-final-20260615/
mobile/QA/screenshots/showcase/
mobile/QA/seed_mobile_showcase_data.sh
mobile/android/app/build.gradle.kts
mobile/android/app/src/main/kotlin/com/skyapp/personal_ledger/MainActivity.kt
mobile/android/app/src/main/kotlin/com/skyapp/personal_ledger/PaymentNotificationParser.kt
mobile/android/app/src/test/kotlin/com/skyapp/personal_ledger/PaymentNotificationParserTest.kt
mobile/assets/
mobile/lib/app/widgets/corgi_illustration.dart
mobile/lib/features/accounts/data/account.dart
mobile/lib/features/accounts/data/account_repository.dart
mobile/lib/features/accounts/data/account_type_rules.dart
mobile/lib/features/api_tokens/data/api_token_repository.dart
mobile/lib/features/auth/application/auth_controller.dart
mobile/lib/features/lendings/data/lending_repository.dart
mobile/lib/features/profile/data/profile_repository.dart
mobile/lib/features/reminders/data/reminder_repository.dart
mobile/lib/features/smart_quick_ledger/data/quick_ledger_draft.dart
mobile/lib/features/smart_quick_ledger/data/quick_ledger_repository.dart
mobile/lib/features/smart_quick_ledger/data/quick_ledger_text_parser.dart
mobile/lib/features/smart_quick_ledger/presentation/smart_quick_ledger_page.dart
mobile/lib/features/transactions/presentation/widgets/quick_transaction_pickers.dart
mobile/pubspec.lock
mobile/pubspec.yaml
mobile/test/app_theme_test.dart
mobile/test/auth_controller_test.dart
mobile/test/quick_ledger_text_parser_test.dart
mobile/test/smart_quick_ledger_widget_test.dart
mobile/test/ui_review_capture_test.dart
output/
scripts/resolve-release-version.sh
scripts/test-resolve-release-version.sh
scripts/verify-clean-checkout.sh
scripts/verify-database-matrix.sh
web/src/api/account.test.ts
web/src/api/account.ts
web/src/api/apiToken.ts
web/src/api/auth.ts
web/src/api/featureApis.test.ts
web/src/api/import.test.ts
web/src/api/import.ts
web/src/api/lending.ts
web/src/api/reminder.ts
web/src/api/setup.ts
web/src/api/template.ts
web/src/main.ts
web/src/stores/auth.test.ts
web/src/stores/auth.ts
web/src/utils/accountSummary.ts
web/src/utils/accountTypeRules.ts
web/src/utils/constants.ts
web/src/utils/ledgerDate.ts
web/src/utils/localDate.ts
web/src/utils/managedTransaction.test.ts
web/src/utils/managedTransaction.ts
web/src/utils/refreshCoordinator.test.ts
web/src/utils/refreshCoordinator.ts
web/src/utils/request.ts
web/src/utils/setupAccess.test.ts
web/src/utils/setupAccess.ts
web/src/utils/tagValues.test.ts
web/src/utils/tagValues.ts
web/src/utils/tokenRefreshPolicy.test.ts
web/src/utils/tokenRefreshPolicy.ts
web/src/utils/transactionDialogOptions.test.ts
web/src/utils/transactionDialogOptions.ts
web/src/utils/transactionListParams.test.ts
web/src/utils/transactionListParams.ts
web/src/views/AccountsView.vue
web/src/views/SetupView.vue
web/src/views/TagView.vue
web/src/views/TemplateView.vue
web/src/views/TransactionsView.vue
```

### Unified Hardening Delta (2026-08-24)

Backend request limits, credential migration, attachment metadata, and supporting contracts:

```text
backend/internal/middleware/body_limit.go
backend/internal/middleware/body_limit_test.go
backend/internal/handler/notification_test.go
backend/internal/service/attachment_barrier.go
backend/internal/service/backup_attachment_recovery.go
backend/internal/service/credential_keyring.go
backend/internal/service/credential_keyring_test.go
backend/internal/service/credential_migration.go
backend/internal/service/credential_migration_test.go
backend/internal/service/evidence.go
backend/internal/service/evidence_test.go
backend/internal/service/storage_sync.go
```

Mobile transport policy, mutation refresh, attachment retry, and runtime validation:

```text
mobile/android/gradle/wrapper/gradle-wrapper.properties
mobile/integration_test/app_real_backend_smoke_test.dart
mobile/lib/core/config/local_http_transport_policy.dart
mobile/lib/core/network/api_client.dart
mobile/lib/core/storage/secure_storage_service.dart
mobile/lib/features/attachments/data/attachment_after_save_exception.dart
mobile/lib/features/attachments/data/attachment_picker_service.dart
mobile/lib/features/attachments/data/attachment_staged_sync.dart
mobile/lib/features/transactions/application/ledger_refresh.dart
mobile/lib/features/transactions/data/transaction_repository.dart
mobile/test/attachment_staged_sync_test.dart
mobile/test/ledger_refresh_test.dart
```

Web mutation refresh, stale-request suppression, accessibility, and dependency settings:

```text
web/e2e/ledger-flow.e2e.ts
web/pnpm-workspace.yaml
web/src/components/Toast.vue
web/src/composables/useLedgerMutation.test.ts
web/src/composables/useLedgerMutation.ts
web/src/utils/requestGeneration.test.ts
web/src/utils/requestGeneration.ts
web/src/views/AccountLogView.vue
web/src/views/BudgetView.vue
web/src/views/LendingView.vue
web/src/views/ReminderView.vue
web/src/views/ReportView.vue
web/src/views/StatisticsView.vue
```

Release governance, deployment truth, layered feature docs, and automated gates:

```text
.forgejo/workflows/ci.yml
.github/dependabot.yml
.github/workflows/release-web.yml
docs/development/deployment.md
docs/development/release-governance.md
docs/features/accounting.md
docs/features/clients.md
docs/features/data-security.md
docs/mobile-real-backend-e2e.md
docs/quality/accessibility-release-evidence-2026-05-27.md
docs/quality/backup-operator-drill-2026-05-27.md
docs/quality/mobile-device-qa-checklist-2026-05-27.md
docs/quality/mobile-platform-qa-2026-05-27.md
docs/quality/mobile-premium-visual-review-2026-05-27.md
docs/quality/release-artifact-evidence-2026-05-27.md
docs/quality/release-notes-candidate-2026-05-27.md
scripts/check-github-actions-pinning.sh
scripts/generate-release-compose.sh
```

### v1.0.9 Publication Preparation (2026-08-24)

Scope-aware Docker/Web pre-tag and post-publication gates:

```text
.github/workflows/release-web.yml
scripts/check-docker-release-evidence.sh
scripts/check-final-release-gates.sh
scripts/check-final-release-runbook.sh
scripts/check-production-readiness.sh
scripts/check-release-notes-candidate.sh
```

Current release, deployment, feature, and remote-governance documentation:

```text
README.md
docs/development/release-governance.md
docs/features/clients.md
docs/features/data-security.md
docs/features/family-ai.md
docs/quality/final-release-runbook-2026-05-27.md
docs/quality/release-change-inventory-2026-05-27.md
docs/quality/release-notes-candidate-2026-05-27.md
docs/release/v1.0.9.md
docs/screenshots/README.md
```

Current-source isolated Web, Android, and iOS runtime screenshots:

```text
docs/screenshots/v1.0.9/README.md
docs/screenshots/v1.0.9/android-home-runtime.png
docs/screenshots/v1.0.9/android-quick-entry-runtime.png
docs/screenshots/v1.0.9/ios-home-runtime.png
docs/screenshots/v1.0.9/web-home-runtime.jpg
docs/screenshots/v1.0.9/web-quick-entry-runtime.jpg
docs/screenshots/v1.0.9/web-transactions-runtime.jpg
```

### Immutable Tag Release Recovery (2026-08-24)

Nested workflow permissions, exact-source Docker identity, zero-job startup recovery, and their
enforced governance contracts:

```text
.github/workflows/docker.yml
.github/workflows/release-web.yml
.github/workflows/release-web-recovery.yml
docs/development/release-governance.md
docs/quality/final-release-runbook-2026-05-27.md
docs/quality/release-change-inventory-2026-05-27.md
scripts/check-docker-release-preflight.sh
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
