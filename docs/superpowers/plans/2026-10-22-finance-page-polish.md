# Finance Page Polish Implementation Plan

> **For agentic workers:** Execute inline with superpowers:executing-plans. Preserve all existing WIP; no staging, commits or pushes.

**Goal:** Apply the approved original-style prototype to transactions, statistics, appearance, debt and family pages.

**Architecture:** Add a small shared page surface, selection control and accessible dialog. Retain the existing API clients, query identity guards, financial commands and preference ownership. Adapt annual report presentation as the existing statistics destination.

**Tech Stack:** Existing Vue 3, TypeScript, Pinia, Tailwind CSS 4 and Lucide. No dependency changes.

**Spec:** `/Users/sky/.codex/visualizations/2026/10/21/ledger-functional-review/native-prototype/设计分析.md`, approved prototype revision `20261022-pages2`.

## Global Constraints

- No changes to HomeView, home widgets, backend, database, attachments, CI or deployment.
- Preserve the existing light/dark preference and navigation preference ownership.
- Tests use an isolated temporary backend or mocked APIs; never write to the preview ledger.
- Preserve real pagination, periods, member budgets, legacy reminders and financial protection rules.
- No fabricated balances, totals, periods, repayment schedules or success feedback.
- No staging, commits or pushes.

## Review Focus

- Filter cancellation and invalid dates must not submit a new query.
- Failed or stale requests must retain their existing identity and retry behavior.
- Modal dismissal must respect busy/pending financial writes and restore focus.
- Empty, disabled and unassigned members must not erase historical expenses.
- Theme/system changes and layout resizing must not discard open form drafts.

### Task 1: Shared surfaces and appearance

**Files:** `web/src/components/ui/FinancePage.vue`, `SelectionControl.vue`, `AppDialog.vue`; `web/src/assets/finance-pages.css`; `web/src/stores/theme.ts`; `AppearanceView.vue`; router and settings entry.

**Interfaces:** Theme exposes `preference`, `setPreference`, and existing `isDark/init/toggle`. Page accepts title/context/icon/actions. Selection accepts string options/modelValue. Dialog retains busy and return/fallback focus contracts.

- [x] Test stored legacy light/dark, explicit system updates, manual override and refresh initialization.
- [x] Implement shared surfaces and appearance without changing global homepage styles.
- [x] Verify unit tests and type checking.

### Task 2: Transactions and statistics

**Files:** `TransactionsView.vue`, `StatisticsView.vue`, `ReportView.vue`; targeted existing/new tests.

- [x] Test filter drafts, query application, shared chart scale, zero and signed values.
- [x] Adapt page frames, menus, filter dialog, chart interactions and annual presentation.
- [x] Retain API request generations, pagination and managed transaction restrictions.
- [x] Verify isolated read/error/filter/chart workflows on desktop and mobile.

### Task 3: Family and debt

**Files:** `FamilyView.vue`, `DebtManagementView.vue`, `DebtView.vue`, debt dialog/allocation components.

- [x] Preserve member budgeting and CRUD; display real attributed/unattributed amounts.
- [x] Add member management dialogs and expandable category rows.
- [x] Unify debt width, remove repeated page heading, keep plans in one column.
- [x] Improve scope selection and sticky allocation totals without changing command semantics.
- [x] Verify cancellation, long content, pending writes, allocation and receipt actions using isolated fixtures.

### Task 4: Integration verification

- [x] Run existing unit suite, production build and relevant isolated E2E.
- [x] Inspect desktop/mobile light/dark screenshots and reduced motion.
- [x] Review the task delta against the saved pre-existing WIP, verify homepage/backend/ledger untouched.
- [x] Update the existing development preview's static Web files only if its serving path is verified; no ledger writes or service migrations.

## Execution Notes

- Baseline: main / b720992; 244 WIP entries; 40 unit files / 368 tests passed.
- WIP snapshots and evidence: `/Users/sky/.codex/visualizations/2026/10/22/ledger-web-adaptation/`.
- Ruling: work in the user-requested existing worktree; a clean worktree would omit the approved WIP.
- Ruling: no commit steps, automated cleanup or deployment. User restrictions override generic skill workflow steps.
- Ruling: use the existing browser and test tooling; no new libraries or CMS/theme engine.

## Acceptance Results

- Unit suite: 43 files / 380 tests passed.
- Production build and bundle budgets passed.
- Chromium: 65 isolated E2E passed; Firefox and WebKit: 34 isolated E2E passed.
- Additional 320px verification: 9 passed across all three engines.
- Independent static review findings fixed and retested.
- Preview static files updated and checked; no ledger data operations, commits or pushes.
- Evidence: `/Users/sky/.codex/visualizations/2026/10/22/ledger-web-adaptation/验收说明.md`.
