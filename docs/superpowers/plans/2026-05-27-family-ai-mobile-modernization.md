# Family AI Mobile Modernization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the next Personal Ledger product layer: lightweight family accounting, OpenAI-compatible AI analysis, and modern premium Flutter mobile interactions.

**Architecture:** Keep the project as a personal/family self-hosted system, not a multi-tenant SaaS. Add family members as an accounting dimension under the existing owner user, add AI analysis through a provider adapter that sends only aggregated snapshots, and modernize Flutter mobile screens through shared design tokens and focused screen upgrades.

**Tech Stack:** Go + Gin + GORM backend, Vue 3 Web, Flutter + Riverpod + GoRouter mobile, SQLite default with PostgreSQL/MySQL compatibility.

---

## File Structure

### New Backend Files

- `backend/internal/model/family_member.go`: family member model.
- `backend/internal/repository/family_member.go`: family member persistence.
- `backend/internal/service/family_member.go`: member CRUD and summary service.
- `backend/internal/handler/family.go`: family API handlers.
- `backend/internal/model/ai.go`: AI provider and AI report models.
- `backend/internal/service/ai_provider.go`: provider CRUD and connection test.
- `backend/internal/service/ai_report.go`: report snapshot and generation orchestration.
- `backend/internal/service/ai_openai_client.go`: OpenAI-compatible HTTP adapter.
- `backend/internal/handler/ai.go`: AI provider and report endpoints.

### Existing Backend Files To Modify

- `backend/internal/model/models.go`: add nullable member fields to transaction/account/budget/account log models or move related models into focused files if the existing pattern allows.
- `backend/internal/database/database.go`: migrate new family and AI models.
- `backend/internal/repository/repository.go`: wire new repositories.
- `backend/internal/service/service.go`: wire new services.
- `backend/internal/handler/handler.go`: register `/family` and `/ai` routes.
- `backend/internal/service/transaction.go`: accept and persist member fields.
- `backend/internal/service/backup.go`: include family members and member fields; exclude raw AI provider keys.

### New Mobile Files

- `mobile/lib/app/theme/motion_tokens.dart`: animation duration and curve constants.
- `mobile/lib/app/widgets/animated_money_text.dart`: reusable animated amount text.
- `mobile/lib/features/family/data/family_repository.dart`: family API client.
- `mobile/lib/features/family/presentation/family_page.dart`: family hub.
- `mobile/lib/features/ai/data/ai_report_repository.dart`: AI reports API client.
- `mobile/lib/features/ai/presentation/ai_reports_page.dart`: weekly/monthly report list and detail.

### Existing Mobile Files To Modify

- `mobile/lib/app/theme/app_theme.dart`: add semantic finance colors, surfaces, radii, and text treatment.
- `mobile/lib/app/router/app_route_paths.dart`: add family and AI report routes.
- `mobile/lib/app/router/app_router.dart`: register family and AI pages.
- `mobile/lib/features/home/presentation/home_page.dart`: modern dashboard sample.
- `mobile/lib/features/transactions/presentation/quick_transaction_page.dart`: prepare bottom-sheet-friendly form and member selector.
- `mobile/lib/features/profile/presentation/profile_page.dart`: add Family and AI report entries.

### Web Files To Modify Later

- `web/src/views/SettingsView.vue`: family member and AI provider settings.
- `web/src/components/TransactionDialog.vue`: member selector.
- `web/src/views/HomeView.vue`: family summary strip and AI report card.
- `web/src/api/*.ts`: family and AI API clients.

## Task 1: Family Member Backend Model And API

**Files:**
- Create: `backend/internal/model/family_member.go`
- Create: `backend/internal/repository/family_member.go`
- Create: `backend/internal/service/family_member.go`
- Create: `backend/internal/handler/family.go`
- Modify: `backend/internal/database/database.go`
- Modify: `backend/internal/repository/repository.go`
- Modify: `backend/internal/service/service.go`
- Modify: `backend/internal/handler/handler.go`
- Test: `backend/internal/service/family_member_test.go`
- Test: `backend/internal/handler/family_test.go`

- [x] **Step 1: Write family member service tests**

Create `backend/internal/service/family_member_test.go` with tests for create, list, update, disable, and default member behavior.

- [x] **Step 2: Run the targeted failing tests**

Run: `cd backend && go test ./internal/service -run FamilyMember -count=1`

Expected: FAIL because the service does not exist.

- [x] **Step 3: Implement model, repository, and service**

Add `FamilyMember` with `UserID`, `Name`, `Relationship`, `Avatar`, `Color`, `SortOrder`, `IsDefault`, and `IsEnabled`. Ensure creating a first member marks it as default.

- [x] **Step 4: Write handler tests**

Create handler tests covering authenticated list/create/update/delete behavior.

- [x] **Step 5: Register routes**

Register:

```text
GET    /api/v1/family/members
POST   /api/v1/family/members
PUT    /api/v1/family/members/:id
DELETE /api/v1/family/members/:id
```

- [x] **Step 6: Run backend tests**

Run: `cd backend && go test ./...`

Expected: PASS.

## Task 2: Transaction Member Fields

**Files:**
- Modify: `backend/internal/model/models.go`
- Modify: `backend/internal/service/transaction.go`
- Modify: `backend/internal/handler/transaction.go`
- Modify: `web/src/api/transaction.ts`
- Modify: `mobile/lib/features/transactions/data/transaction_models.dart`
- Test: `backend/internal/service/transaction_test.go`
- Test: `mobile/test/quick_transaction_form_validation_test.dart`

- [x] **Step 1: Add failing backend tests**

Add tests proving transaction create/update can persist `member_id` and `paid_by_member_id`, and rejects member IDs owned by another user.

- [x] **Step 2: Run targeted backend tests**

Run: `cd backend && go test ./internal/service -run Transaction -count=1`

Expected: FAIL until member fields are implemented.

- [x] **Step 3: Add nullable member fields**

Add:

```go
MemberID       *string `gorm:"size:36;index" json:"member_id,omitempty"`
PaidByMemberID *string `gorm:"size:36;index" json:"paid_by_member_id,omitempty"`
```

Use nullable fields to preserve backward compatibility.

- [x] **Step 4: Validate member ownership**

Transaction service must verify supplied member IDs belong to the current owner user.

- [x] **Step 5: Update clients**

Add optional `member_id` and `paid_by_member_id` to Web and Flutter transaction models.

- [x] **Step 6: Run verification**

Run:

```bash
cd backend && go test ./...
cd mobile && flutter test
```

Expected: PASS.

## Task 3: Family Summary API

**Files:**
- Modify: `backend/internal/repository/transaction.go`
- Modify: `backend/internal/service/family_member.go`
- Modify: `backend/internal/handler/family.go`
- Test: `backend/internal/service/family_member_test.go`

- [x] **Step 1: Write family summary tests**

Test monthly member spending ranking, total family expense, and empty-state response.

- [x] **Step 2: Implement repository aggregation**

Aggregate expense totals grouped by `member_id` for a date range.

- [x] **Step 3: Add endpoint**

Register:

```text
GET /api/v1/family/summary?month=YYYY-MM
```

- [x] **Step 4: Run backend tests**

Run: `cd backend && go test ./...`

Expected: PASS.

## Task 4: AI Provider Backend

**Files:**
- Create: `backend/internal/model/ai.go`
- Create: `backend/internal/service/ai_provider.go`
- Create: `backend/internal/service/ai_openai_client.go`
- Create: `backend/internal/handler/ai.go`
- Modify: `backend/internal/database/database.go`
- Modify: `backend/internal/service/service.go`
- Modify: `backend/internal/handler/handler.go`
- Test: `backend/internal/service/ai_provider_test.go`
- Test: `backend/internal/handler/ai_test.go`

- [x] **Step 1: Write provider tests**

Test create/list/update/delete and assert list responses never include raw API keys.

- [x] **Step 2: Implement provider model and service**

Store provider name, type, base URL, model, enabled flag, and protected API key value.

- [x] **Step 3: Implement OpenAI-compatible URL normalization**

Normalize `https://api.example.com` to `https://api.example.com/v1/chat/completions`, but keep existing `/v1` suffix stable.

- [x] **Step 4: Add connection test endpoint**

Use a non-financial prompt such as `Reply with ok.` and a short timeout.

- [x] **Step 5: Run backend tests**

Run: `cd backend && go test ./...`

Expected: PASS.

## Task 5: AI Weekly Report Generation

**Files:**
- Modify: `backend/internal/model/ai.go`
- Create: `backend/internal/service/ai_report.go`
- Modify: `backend/internal/service/statistics.go`
- Modify: `backend/internal/handler/ai.go`
- Test: `backend/internal/service/ai_report_test.go`

- [x] **Step 1: Write report generation tests with a fake AI server**

Use `httptest.Server` to return a deterministic OpenAI-compatible response.

- [x] **Step 2: Build local snapshot generation**

Generate period, income total, expense total, net cashflow, budget status, top categories, member totals, and account changes.

- [x] **Step 3: Exclude raw sensitive data**

Ensure snapshot does not include passwords, tokens, webhook URLs, attachment contents, or raw transaction remarks by default.

- [x] **Step 4: Store report output**

Persist report status, snapshot JSON, structured content JSON, model, provider, and prompt version.

- [x] **Step 5: Register report endpoints**

Register:

```text
GET    /api/v1/ai/reports
POST   /api/v1/ai/reports/generate
GET    /api/v1/ai/reports/:id
DELETE /api/v1/ai/reports/:id
```

- [x] **Step 6: Run backend tests**

Run: `cd backend && go test ./...`

Expected: PASS.

## Task 6: Flutter Design Tokens And Animated Money

**Files:**
- Create: `mobile/lib/app/theme/motion_tokens.dart`
- Create: `mobile/lib/app/widgets/animated_money_text.dart`
- Modify: `mobile/lib/app/theme/app_theme.dart`
- Test: `mobile/test/animated_money_text_test.dart`

- [x] **Step 1: Write widget tests**

Test that `AnimatedMoneyText` renders a formatted amount and updates when amount changes.

- [x] **Step 2: Add motion tokens**

Define short, medium, long durations and standard curves.

- [x] **Step 3: Implement animated money widget**

Use `TweenAnimationBuilder<double>` and tabular figure styling.

- [x] **Step 4: Run Flutter verification**

Run:

```bash
cd mobile && flutter analyze
cd mobile && flutter test
```

Expected: PASS.

## Task 7: Flutter Family And AI Navigation Shell

**Files:**
- Create: `mobile/lib/features/family/data/family_repository.dart`
- Create: `mobile/lib/features/family/presentation/family_page.dart`
- Create: `mobile/lib/features/ai/data/ai_report_repository.dart`
- Create: `mobile/lib/features/ai/presentation/ai_reports_page.dart`
- Modify: `mobile/lib/app/router/app_route_paths.dart`
- Modify: `mobile/lib/app/router/app_router.dart`
- Modify: `mobile/lib/features/profile/presentation/profile_page.dart`
- Test: `mobile/test/family_widget_test.dart`
- Test: `mobile/test/ai_reports_widget_test.dart`

- [x] **Step 1: Write navigation tests**

Test Profile page exposes Family and AI Reports entries and can navigate to each page.

- [x] **Step 2: Implement minimal repository models**

Add models for member list and AI report list.

- [x] **Step 3: Implement production-quality initial pages**

Pages must show real loading, empty, error, and data states. Do not use copy that implies unfinished work.

- [x] **Step 4: Register routes**

Add `/family` and `/ai-reports` routes.

- [x] **Step 5: Run Flutter verification**

Run:

```bash
cd mobile && flutter analyze
cd mobile && flutter test
```

Expected: PASS.

## Task 8: Modern Mobile Home Sample

**Files:**
- Modify: `mobile/lib/features/home/presentation/home_page.dart`
- Create: focused widgets under `mobile/lib/features/home/presentation/widgets/`
- Test: `mobile/test/home_widget_test.dart`

- [x] **Step 1: Extend home widget tests**

Assert the home page displays primary cashflow, budget progress, quick action, and family summary when data exists.

- [x] **Step 2: Extract dashboard widgets**

Create focused widgets for hero summary, cashflow strip, budget progress, family strip, and risk cards.

- [x] **Step 3: Add motion**

Use `AnimatedMoneyText`, `AnimatedSwitcher`, and transform/opacity animations only.

- [x] **Step 4: Verify mobile layout**

Run:

```bash
cd mobile && flutter analyze
cd mobile && flutter test
RUN_FLUTTER_TESTER_E2E=1 RUN_ANDROID_E2E=0 RUN_IOS_E2E=0 ./scripts/verify-mobile-e2e.sh
```

Expected: PASS.

## Task 9: Quick Transaction Bottom Sheet Preparation

**Files:**
- Modify: `mobile/lib/features/transactions/presentation/quick_transaction_page.dart`
- Modify: `mobile/lib/features/main/presentation/main_shell_page.dart`
- Test: `mobile/test/quick_transaction_form_validation_test.dart`
- Test: `mobile/test/main_shell_widget_test.dart`

- [x] **Step 1: Write interaction tests**

Test tapping quick transaction opens the form, saving shows loading, and success returns to the prior context.

- [x] **Step 2: Make quick transaction form sheet-friendly**

Separate form content from page scaffold so it can render in a full page or modal bottom sheet.

- [x] **Step 3: Add member selector**

Show member selector only when family members exist.

- [x] **Step 4: Run Flutter tests**

Run:

```bash
cd mobile && flutter analyze
cd mobile && flutter test
```

Expected: PASS.

## Task 10: Release-Level Verification

**Files:**
- Modify: `scripts/verify-mobile-e2e.sh` only if needed.
- Modify: docs only for evidence updates.

- [x] **Step 1: Run backend verification**

Run: `cd backend && go test ./...`

Expected: PASS.

- [x] **Step 2: Run Web verification**

Run: `cd web && pnpm run build`

Expected: PASS.

- [x] **Step 3: Run Flutter verification**

Run:

```bash
cd mobile && flutter analyze
cd mobile && flutter test
```

Expected: PASS.

- [x] **Step 4: Run real backend mobile E2E**

Run:

```bash
RUN_FLUTTER_TESTER_E2E=1 RUN_ANDROID_E2E=0 RUN_IOS_E2E=0 ./scripts/verify-mobile-e2e.sh
```

Expected: PASS.

- [x] **Step 5: Run public safety check**

Run:

```bash
./scripts/check-public-git-safety.sh
git diff --check
```

Expected: PASS.

## Self-Review Checklist

- Family mode remains a trusted single-deployment feature, not SaaS multi-tenancy.
- AI analysis sends aggregated snapshots, not full raw financial records by default.
- Mobile modernization prioritizes Home and Quick Transaction before broad visual churn.
- All schema additions are nullable or backward-compatible in the first implementation.
- Web UI changes are minimal until backend and mobile foundations are stable.
