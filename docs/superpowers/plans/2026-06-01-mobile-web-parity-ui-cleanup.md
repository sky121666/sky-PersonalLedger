# Mobile Web-Parity UI Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Flutter mobile app preserve Web-side business functionality while removing non-functional prompt/status/radar/flow/explanation UI so the app behaves like a clean, high-frequency personal ledger app.

**Architecture:** Treat `web/src/router/index.ts` and the Web view/dialog implementations as the functional baseline. Flutter pages must keep the same business operations but present them as mobile-native forms, lists, filters, and settings, not cockpit dashboards or explanatory panels.

**Tech Stack:** Flutter, Riverpod, GoRouter, existing mobile repositories/controllers, existing widget tests and `flutter analyze`.

---

## Product Target

The mobile app must be a usable ledger client, not a feature showcase.

Functional parity means:
- Keep every Web business capability that already exists: login/setup, home, transactions, statistics, settings, accounts, categories, budgets, reminders, lendings, yearly report, family, AI reports, account logs, notifications, API tokens, security, data management, tags, templates, quick transaction.
- Do not delete data capabilities, repository calls, validation, upload, backup, import/export, or security confirmations.
- Remove UI that only explains, narrates, scores, summarizes, advertises readiness, or repeats selected data without letting the user act.

Clean mobile UI means:
- High-frequency screens show actions first.
- Management screens show CRUD lists and forms.
- Settings screens show settings rows and explicit forms.
- Analytical screens show actual charts/tables/results only.
- Dangerous operations keep confirmation, but without decorative risk dashboards.

## Global Removal Rules

Remove or rewrite UI containing these concepts unless it directly performs an operation:

| Remove Pattern | Examples | Replacement |
|---|---|---|
| Radar/matrix/cockpit | `雷达`, `矩阵`, `Cockpit`, `Deck` | List, form, chart, or nothing |
| Command/center/hub | `指挥`, `中枢`, `CommandCenter`, `Hub` | Page title plus actions |
| Signal/readiness/status noise | `信号`, `就绪`, `等待`, `状态 x/3` | Inline validation only |
| Flow/route/narrative | `动线`, `流程`, `叙事` | Native field order |
| Health/score/posture | `健康`, `评分`, `态势` | Actual value only if needed |
| Coverage/quality | `覆盖`, `质量层` | Remove unless user-selected filter |
| Capability/explanation copy | `用于`, `帮助`, `建议`, `能力` | Button label or field label |
| Repeated selected-data cards | account/category/member recap | Remove; the selected field already shows it |

## Functional Baseline

### Web Routes

| Web Route | Web View | Mobile Equivalent |
|---|---|---|
| `/` | `HomeView.vue` | `/home` |
| `/transactions` | `TransactionsView.vue` | `/transactions` |
| Transaction dialog | `TransactionDialog.vue` | `/quick-transaction` |
| `/statistics` | `StatisticsView.vue` | `/statistics` |
| `/settings` | `SettingsView.vue` | `/profile` plus secondary settings pages |
| `/accounts` | `AccountsView.vue` | `/accounts` |
| `/categories` | `CategoryView.vue` | `/categories` |
| `/budgets` | `BudgetView.vue` | `/budgets` |
| `/reminders` | `ReminderView.vue` | `/reminders` |
| `/lendings` | `LendingView.vue` | `/lendings` |
| `/report` | `ReportView.vue` | `/yearly-report` |
| `/family` | `FamilyView.vue` | `/family` |
| `/ai` | `AIView.vue` | `/ai-reports` |
| `/account-logs` | `AccountLogView.vue` | `/account-logs` |

## Page-Level Requirements

### Core Navigation

**Files:**
- Modify: `mobile/lib/features/main/presentation/main_shell_page.dart`
- Test: `mobile/test/main_shell_widget_test.dart`

Requirements:
- Bottom navigation remains `首页 / 明细 / 统计 / 我的`.
- The central/right primary action is a plain `+` for quick transaction.
- No readiness/status text near the `+`.
- No “入口”, “就绪”, “能力” labels around navigation.

Acceptance:
- Main tabs are reachable.
- `+` opens quick transaction.
- No non-functional status text appears in the shell.

### Quick Transaction

**Files:**
- Modify: `mobile/lib/features/transactions/presentation/quick_transaction_page.dart`
- Test: `mobile/test/quick_transaction_form_validation_test.dart`

Requirements:
- Match Web `TransactionDialog.vue` functional fields.
- First screen order: type selector, amount, account, category/to-account.
- Then compact date, remark.
- Family member, tags, attachments are retained but grouped under optional/more area or placed after required fields.
- Remove `_QuickTransactionHero`, `_QuickEntryFlowPanel`, `_TransactionFlowHint`, `_QuickReadinessPill`, `_QuickEntryFlowNode`, `_QuickFlowConnector`, `_QuickEntryFlowMeta`.
- No “金额完成”, “等待金额”, “记账动线”, “凭证状态”, “家庭归属”.

Acceptance:
- Income requires amount/account/category.
- Expense requires amount/account/category.
- Transfer requires amount/from-account/to-account and rejects identical accounts.
- Existing edit flow still loads saved values.
- Attachments still upload after save/update.

### Transaction Details

**Files:**
- Modify: `mobile/lib/features/transactions/presentation/transaction_details_page.dart`
- Test: `mobile/test/transaction_details_widget_test.dart`

Requirements:
- Keep search, filters, multi-select delete, edit, pagination.
- Remove overview cards that repeat list totals unless they are compact and directly useful.
- Replace “交易明细总览/筛选结果概览” with simple list header or remove.
- Remove `_TransactionMetaPill` if it only repeats account/category/member metadata already visible in row.

Acceptance:
- User can find, filter, edit, delete transactions.
- First viewport shows transaction list, not a dashboard.

### Attachments

**Files:**
- Modify: `mobile/lib/features/attachments/presentation/attachment_picker_field.dart`
- Test: `mobile/test/attachment_picker_field_test.dart`

Requirements:
- Keep add, preview, remove, upload progress.
- Remove `_AttachmentSignalDeck`, `_AttachmentEvidenceMatrix`, `_AttachmentMatrixTile`, `_AttachmentMatrixPill`, `_AttachmentSignalTile`.
- No “保存状态”, “证据矩阵”, “状态 x/3”.

Acceptance:
- Attachments can be selected, previewed, removed, uploaded.
- No decorative status matrix remains.

### Home

**Files:**
- Modify: `mobile/lib/features/home/presentation/home_page.dart`
- Modify: `mobile/lib/features/home/presentation/widgets/home_dashboard_widgets.dart`
- Test: `mobile/test/home_widget_test.dart`

Requirements:
- Keep net assets, monthly income/expense/balance, recent transactions, budget/account summary if compact.
- Remove “pulse”, “signal”, “overview” cards that repeat the same totals.
- No feature promotion panels.

Acceptance:
- First viewport answers: current money, month cashflow, recent activity.

### Accounts

**Files:**
- Modify: `mobile/lib/features/accounts/presentation/accounts_page.dart`
- Test: `mobile/test/accounts_widget_test.dart`

Requirements:
- Keep account list, create/edit/archive/sort, account balance display.
- Remove `_AccountPortfolioControlStrip`, `_AccountPortfolioMatrixPanel`, `_AccountControlMetric`, decorative `健康/态势/覆盖` copy.
- Keep only one compact summary if needed: total assets, liabilities, net assets.

Acceptance:
- Account management works.
- Normal/archived accounts are clear.
- No matrix/control-strip/dashboard before list.

### Account Logs

**Files:**
- Modify: `mobile/lib/features/account_logs/presentation/account_log_page.dart`
- Test: `mobile/test/account_log_widget_test.dart`

Requirements:
- Keep account filter and ledger log list.
- Remove “流水审计中枢”, `_FlowSignalTile`, `_AuditStatusPill` if decorative.
- First viewport should show filters/list.

Acceptance:
- Logs load for all accounts and by account id.

### Categories

**Files:**
- Modify: `mobile/lib/features/categories/presentation/categories_page.dart`
- Test: `mobile/test/category_widget_test.dart`

Requirements:
- Keep income/expense segmented switch, category list, create/edit/delete, color/icon fields.
- Remove `_CategorySpectrumPanel`, `_CategorySignalPanel`, `_CategoryMetaChip`, “健康图标”, “颜色覆盖/图标覆盖”.

Acceptance:
- Category CRUD remains.
- No coverage/spectrum panels remain.

### Tags

**Files:**
- Modify: `mobile/lib/features/tags/presentation/tag_page.dart`
- Test: `mobile/test/tag_widget_test.dart`

Requirements:
- Keep tag list, create/edit/delete, color/icon fields.
- Remove `_TagSpectrumPanel`, `_TagOrchestrationPanel`, `_TagFlowStep`, `_TagSignalPanel`, `_TagMetaChip` if decorative.

Acceptance:
- Tag CRUD remains.
- No orchestration/signal copy remains.

### Templates

**Files:**
- Modify: `mobile/lib/features/templates/presentation/template_page.dart`
- Test: `mobile/test/template_widget_test.dart`

Requirements:
- Keep template list, create/edit/delete, execute/apply template.
- Remove `_TemplateOrchestrationPanel`, `_TemplateAutomationStrip`, `_TemplateExecutionMatrix`, `_TemplateFlowMetric`, matrix/status pills that do not perform actions.

Acceptance:
- User can create and use templates.
- Page starts with list/actions, not reuse metrics.

### Budgets

**Files:**
- Modify: `mobile/lib/features/budgets/presentation/budget_page.dart`
- Test: `mobile/test/budget_widget_test.dart`

Requirements:
- Keep budget summary, budget list, create/edit/delete, progress and threshold fields.
- Remove `_BudgetCommandCenter`, `_BudgetFamilyHubPanel`, `_BudgetGuardrailMatrix`, `_BudgetSignalPill`, `_BudgetCommandMetric` if they repeat non-action metrics.

Acceptance:
- Budget list and edit form work.
- Alerts/progress remain only where tied to a budget row.

### Reminders

**Files:**
- Modify: `mobile/lib/features/reminders/presentation/reminder_page.dart`
- Test: `mobile/test/reminder_widget_test.dart`

Requirements:
- Keep debt/reminder list, create/edit/delete, record payment, active/inactive/paid sections.
- Remove `_ReminderStatusGrid`, `_DebtSignalPill`, `_ReminderDebtPanel`, `_ReminderGuardrailMatrix`, `_ReminderSignalMetric`, repeated meta pills unless needed on list row.

Acceptance:
- Reminder operations work.
- No “凭证状态/上岸/节奏” dashboard remains.

### Lendings

**Files:**
- Modify: `mobile/lib/features/lendings/presentation/lending_page.dart`
- Test: `mobile/test/lending_widget_test.dart`

Requirements:
- Keep borrow/lend list, create/edit/delete, payment, close/reopen.
- Remove `_LendingRelationshipHub`, `_LendingRecoveryFlowPanel`, `_RecoveryFlowStep`, `_LendingProgressPanel`, signal/meta pills that repeat row data.

Acceptance:
- Lending operations work.
- No “往来关系中枢/回款动线” remains.

### Family

**Files:**
- Modify: `mobile/lib/features/family/presentation/family_page.dart`
- Test: `mobile/test/family_widget_test.dart`

Requirements:
- Keep family summary if necessary, member list, add/edit/delete/toggle member, budget relation if functional.
- Remove `_FamilyCollaborationHub`, `_FamilyReadinessSurface`, `_FamilyHubMetric`, `_FamilyReadinessTile`, readiness copy.

Acceptance:
- Member management works.
- Page reads like member management, not collaboration cockpit.

### Statistics

**Files:**
- Modify: `mobile/lib/features/statistics/presentation/mobile_statistics_page.dart`
- Test: `mobile/test/statistics_widget_test.dart`

Requirements:
- Keep date/month selector, income/expense/balance charts, category ranking.
- Remove `_StatisticsDataCockpit`, `_StatisticsAiInputPanel`, `_OverviewInsightStrip`, `_InsightChip`, `趋势覆盖`, `AI 输入`.

Acceptance:
- Actual charts/data remain.
- No AI/input/status panels on statistics.

### Yearly Report

**Files:**
- Modify: `mobile/lib/features/reports/presentation/yearly_report_page.dart`
- Test: `mobile/test/yearly_report_widget_test.dart`

Requirements:
- Keep year selector, yearly summary, monthly trend, top categories.
- Remove `_YearlyInsightDeck`, `_YearlyInsightBadge`, `_AnnualSignalTile`, `_YearlySignalPill` if decorative.

Acceptance:
- Report data remains clear.
- No narrative/radar/signal layer remains.

### AI Reports

**Files:**
- Modify: `mobile/lib/features/ai/presentation/ai_reports_page.dart`
- Test: `mobile/test/ai_reports_widget_test.dart`

Requirements:
- Keep AI config, generate report, report list, schedule settings.
- Remove command center, provider signal strips, insight meters, engineering/provider status language not required for the user.
- Use “AI 服务” in visible text, not Provider/网关/生产态 unless directly configuring API.

Acceptance:
- User can configure and generate AI reports.
- No engineering dashboard copy remains.

### Notifications

**Files:**
- Modify: `mobile/lib/features/notifications/presentation/notification_settings_page.dart`
- Test: `mobile/test/notification_widget_test.dart`

Requirements:
- Keep channel forms: WeCom, DingTalk, email, webhook.
- Keep test buttons and reminder rule toggles.
- Remove `_ChannelRouteMatrix`, `_NotificationRuleMatrix`, `_ChannelSignalTile`, `_RuleSignalTile` unless they are direct controls.

Acceptance:
- Channel configuration and test actions work.
- Page behaves like settings forms.

### Security

**Files:**
- Modify: `mobile/lib/features/security/presentation/security_settings_page.dart`
- Test: `mobile/test/security_settings_widget_test.dart`

Requirements:
- Keep change password form, entry path enable/generate/disable.
- Remove `_SecurityFlowStrip`, `_SecurityFlowTile`, `_EntryGuardrailPanel` if they only explain risk.
- Keep explicit confirmation/error messages.

Acceptance:
- Password and entry path operations work.
- No posture/flow dashboard remains.

### API Tokens

**Files:**
- Modify: `mobile/lib/features/api_tokens/presentation/api_token_page.dart`
- Test: `mobile/test/api_token_widget_test.dart`

Requirements:
- Keep create token, display one-time token, token list, revoke.
- Remove `_TokenChannelConsole`, `_TokenChannelStatusPill`, decorative panel headers.

Acceptance:
- Token lifecycle works.
- No authorization exposure dashboard remains.

### Data Management

**Files:**
- Modify: `mobile/lib/features/data_management/presentation/data_management_page.dart`
- Test: `mobile/test/data_management_widget_test.dart`

Requirements:
- Keep backup download, CSV export, restore, auto backup settings, backup list.
- Remove `_DataRecoveryMatrix`, `_AutoBackupOrchestrationPanel`, `_BackupFileSignal`, `_ActionControlStrip`, decorative risk signals.
- Keep destructive confirmation dialogs.

Acceptance:
- Backup/restore/export operations work.
- Dangerous restore still requires explicit confirmation.

### Auth And Setup

**Files:**
- Modify: `mobile/lib/features/auth/presentation/login_page.dart`
- Modify: `mobile/lib/features/auth/presentation/setup_password_page.dart`
- Modify: `mobile/lib/features/server_config/presentation/server_config_page.dart`
- Modify: `mobile/lib/features/bootstrap/presentation/bootstrap_page.dart`
- Modify: `mobile/lib/app/widgets/auth_flow_shell.dart`
- Test: `mobile/test/auth_flow_widget_test.dart`
- Test: `mobile/test/bootstrap_widget_test.dart`
- Test: `mobile/test/server_config_widget_test.dart`

Requirements:
- Login/setup/server config are simple forms.
- Remove initialization matrices, signal decks, status strips, long explanatory copy.
- Keep validation, loading, error, change server.

Acceptance:
- First-run, login, and server change flows still work.

## Visual System Requirements

Apply across all modified pages:
- Maximum one primary action per screen.
- Cards only for repeated list items, forms, or dangerous confirmation surfaces.
- No card-inside-card layout.
- Use labels, rows, tabs, segmented controls, toggles, dropdowns, and buttons.
- Do not display explanatory text when the field label already explains the action.
- Keep touch targets at least 44-48 px.
- Respect Android 120 Hz feel by reducing heavy entrance animation and nested animated containers.
- Avoid repeatedly wrapping every page section in `PremiumSurface`.

## Verification Strategy

Run after each task group:

```bash
cd /Users/sky/项目/sky-PersonalLedger/mobile
flutter analyze
```

Run relevant widget tests:

```bash
cd /Users/sky/项目/sky-PersonalLedger/mobile
flutter test test/quick_transaction_form_validation_test.dart
flutter test test/transaction_details_widget_test.dart
flutter test test/accounts_widget_test.dart
flutter test test/category_widget_test.dart
flutter test test/tag_widget_test.dart
flutter test test/template_widget_test.dart
flutter test test/budget_widget_test.dart
flutter test test/reminder_widget_test.dart
flutter test test/lending_widget_test.dart
flutter test test/family_widget_test.dart
flutter test test/statistics_widget_test.dart
flutter test test/ai_reports_widget_test.dart
flutter test test/notification_widget_test.dart
flutter test test/security_settings_widget_test.dart
flutter test test/api_token_widget_test.dart
flutter test test/data_management_widget_test.dart
```

Build and install:

```bash
cd /Users/sky/项目/sky-PersonalLedger/mobile
flutter build apk --profile
adb devices -l
adb -s 8413dfa50722 install -r build/app/outputs/flutter-apk/app-profile.apk
adb -s 8413dfa50722 shell monkey -p com.skyapp.personal_ledger -c android.intent.category.LAUNCHER 1
```

UI text scan:

```bash
cd /Users/sky/项目/sky-PersonalLedger
rg -n "雷达|洞察|覆盖|健康|指挥|质量|态势|动线|信号|就绪|暴露面|节奏|中枢|矩阵|Cockpit|Command|Signal|Readiness|Orchestration|Matrix|Radar|Hub" mobile/lib/features/*/presentation/*.dart mobile/lib/app/widgets/*.dart
```

Expected:
- Matches should either be gone or justified as true business terms.

## Execution Order

### Task 1: Quick Transaction And Attachments

**Files:**
- Modify: `mobile/lib/features/transactions/presentation/quick_transaction_page.dart`
- Modify: `mobile/lib/features/attachments/presentation/attachment_picker_field.dart`
- Test: `mobile/test/quick_transaction_form_validation_test.dart`
- Test: `mobile/test/attachment_picker_field_test.dart`

- [ ] Remove quick transaction hero/flow/hint/status classes and render calls.
- [ ] Reorder quick transaction into pure form sequence.
- [ ] Collapse or move optional member/tag/attachment fields below required inputs.
- [ ] Strip attachment signal/matrix UI.
- [ ] Run targeted tests and `flutter analyze`.

### Task 2: Core Ledger Lists

**Files:**
- Modify: `mobile/lib/features/transactions/presentation/transaction_details_page.dart`
- Modify: `mobile/lib/features/account_logs/presentation/account_log_page.dart`
- Test: `mobile/test/transaction_details_widget_test.dart`
- Test: `mobile/test/account_log_widget_test.dart`

- [ ] Remove decorative overview/audit/signal panels.
- [ ] Ensure first viewport shows filters and actual list rows.
- [ ] Preserve edit/delete/multi-select/pagination/log filtering.
- [ ] Run targeted tests and `flutter analyze`.

### Task 3: Management Utilities

**Files:**
- Modify: `mobile/lib/features/accounts/presentation/accounts_page.dart`
- Modify: `mobile/lib/features/categories/presentation/categories_page.dart`
- Modify: `mobile/lib/features/tags/presentation/tag_page.dart`
- Modify: `mobile/lib/features/templates/presentation/template_page.dart`
- Test matching widget tests.

- [ ] Convert pages to list + form + action structure.
- [ ] Remove spectrum/orchestration/matrix/control strip components.
- [ ] Preserve CRUD and template execution.
- [ ] Run targeted tests and `flutter analyze`.

### Task 4: Budget, Reminder, Lending, Family

**Files:**
- Modify: `mobile/lib/features/budgets/presentation/budget_page.dart`
- Modify: `mobile/lib/features/reminders/presentation/reminder_page.dart`
- Modify: `mobile/lib/features/lendings/presentation/lending_page.dart`
- Modify: `mobile/lib/features/family/presentation/family_page.dart`
- Test matching widget tests.

- [ ] Keep operational lists/forms.
- [ ] Remove command/hub/readiness/guardrail/progress panels unless they are direct row-level state.
- [ ] Preserve payment, close/reopen, member operations.
- [ ] Run targeted tests and `flutter analyze`.

### Task 5: Analytics And AI

**Files:**
- Modify: `mobile/lib/features/statistics/presentation/mobile_statistics_page.dart`
- Modify: `mobile/lib/features/reports/presentation/yearly_report_page.dart`
- Modify: `mobile/lib/features/ai/presentation/ai_reports_page.dart`
- Test matching widget tests.

- [ ] Keep charts, report lists, generation/config forms.
- [ ] Remove cockpit/insight/signal/engineering provider panels.
- [ ] Ensure visible AI wording is user-facing.
- [ ] Run targeted tests and `flutter analyze`.

### Task 6: Settings, Security, Data

**Files:**
- Modify: `mobile/lib/features/notifications/presentation/notification_settings_page.dart`
- Modify: `mobile/lib/features/security/presentation/security_settings_page.dart`
- Modify: `mobile/lib/features/api_tokens/presentation/api_token_page.dart`
- Modify: `mobile/lib/features/data_management/presentation/data_management_page.dart`
- Test matching widget tests.

- [ ] Convert settings pages to forms and setting rows.
- [ ] Remove route matrices, token consoles, recovery matrices, orchestration panels.
- [ ] Preserve test buttons, revoke, restore confirmation, auto backup settings.
- [ ] Run targeted tests and `flutter analyze`.

### Task 7: Auth, Shell, Final Verification

**Files:**
- Modify: auth/setup/server/bootstrap/shell files listed above.
- Test matching widget tests.

- [ ] Simplify startup/login/setup/server forms.
- [ ] Verify bottom navigation and `+` action.
- [ ] Run full `flutter analyze`.
- [ ] Run representative widget test batch.
- [ ] Build profile APK.
- [ ] Install and launch on device.
- [ ] Run UI text scan and inspect remaining matches.

## Definition Of Done

- Mobile retains all Web baseline business capabilities.
- No high-frequency screen starts with decorative status/explanation panels.
- `记一笔` first screen is a pure input form.
- Management pages are CRUD-first.
- Settings pages are form-first.
- Analytical pages show actual data visualizations/results only.
- `flutter analyze` passes.
- Relevant widget tests pass or failures are documented with exact reasons.
- Android profile APK builds, installs, and launches on the connected device.
