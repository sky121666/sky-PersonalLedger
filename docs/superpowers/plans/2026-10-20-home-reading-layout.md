# Home Reading Layout Implementation Plan

> **For agentic workers:** Use executing-plans inline with test-driven-development. Do not stage, commit or push.

**Goal:** Restore the original centered reading layout while preserving configurable widgets and saved desktop/mobile preferences.

**Architecture:** Keep the current widget catalog, renderers, read models and preference envelope. Project existing sizes into full/half-width rows; use content-driven row heights instead of square units. Share the projection with the gallery and preserve actual DOM geometry for dragging.

**Tech Stack:** Existing Vue 3, TypeScript, CSS Grid, Vitest and Playwright; no dependency changes.

**Spec:** User-approved analysis in the current conversation; original `HEAD:web/src/views/HomeView.vue` and `docs/screenshots/v1.0.9/web-home-runtime.jpg` supply the structural baseline.

## Global Constraints

- Preserve all existing WIP; work and test in a temporary source copy, then synchronize only verified incremental edits.
- No ledger, backend, schema, API, dependency, authentication, CI or Docker changes.
- Keep the existing persisted IDs, widget collection, per-device order and size values; do not reset existing preferences.
- Keep 768px centered home container, current card surfaces, colors and typography.
- A small widget uses half a row where space permits; medium/large use a full row. Mobile reminders receive a full-width display projection without changing saved sizes.
- Card height follows content with component-specific minimum heights. Large transaction summaries show five rows and medium summaries three; full history remains in transactions.
- No commits, staging, pushing, production data access or backend preview restart.

## Review Focus

- Existing custom order, per-device size and empty layouts must round-trip without normalization/reset.
- Long names, large amounts and 200% text must grow rather than clip or create nested vertical scrolling.
- Gallery and home must use the same width projection; preview height varies with its sample content.
- Dragging different-height rows must preserve ghost geometry, source order, cancellation and edge scrolling.
- Mobile gallery list and editing controls must remain reachable at 320px and avoid obscuring content.

### Task 1: Layout projection and default baseline

**Files:** `web/src/components/home/layout.ts`, `layout.test.ts`, `model.ts`, `model.test.ts`.

- [x] Add failing tests: medium/large full row, small half row, large no forced double row, mobile reminders widen without modifying stored size.
- [x] Update packing while preserving deterministic source order and legacy `ColumnCount` callers.
- [x] Default only: asset, accounts, monthly flow, budget, reminders, transactions; mobile reminders medium. Verify existing layouts are untouched.
- [x] Run catalog/layout/preference/store tests.

### Task 2: Content heights, gallery and edit controls

**Files:** `WidgetGrid.vue`, `WidgetGallery.vue`, `WidgetFrame.vue`, `HomeWidget.vue`, `widgets/TransactionsWidget.vue`, `widgets/ReminderWidget.vue`, `web/src/assets/home-cards.css`, existing E2E files.

- [x] Add failing browser checks for full-row widths, distinct content heights, five visible transactions without nested scrolling and gallery width projection.
- [x] Use automatic row heights and semantic minimum heights; retain overflow handling for horizontal account strips.
- [x] Keep phone editing compact: move removal into the existing options menu, retain drag and menu access and desktop removal.
- [x] Use a bounded vertical mobile gallery list and content-driven previews.
- [x] Verify existing save/cancel/undo, keyboard and pointer drag, privacy, navigation and gallery flows.

### Task 3: Verification and preview delivery

**Files:** existing E2E suites; new `docs/development/2026-10-20-home-reading-layout.md` and runtime screenshots.

- [x] Run full Vitest, type checks/build, brace/attachment/bundle checks in the temporary copy.
- [x] Run affected E2E across Chromium, Firefox and WebKit against fresh temporary DB/uploads/backups using the existing harness.
- [x] Obtain an independent read-only review limited to this task's incremental changes; address material findings with regression coverage.
- [x] Compare original WIP hashes before synchronizing changed source files.
- [x] Update only the established Demo frontend dist, verify HTTP content hashes and inspect desktop/phone using existing Demo.
- [x] Record evidence, actual test results and untested physical-device/browser-version boundaries.

## Execution Record

- Baseline: main, HEAD `b7209927e44eb8f683730a975d1889a912322f8a`; existing WIP retained.
- Temporary copy: `/var/folders/l6/smy8mmk15898tpm0vddrbyt00000gn/T/sky-home-flow-20261020-4s20hpqz/candidate`.
- Ruling: existing approval covers local layout implementation; no new worktree, branch, commit or preference migration is needed. Preserve the existing checkout and use an isolated source copy.

- Task 1: complete; legacy preferences retained; narrow content below 400px projects to one column without rewriting stored sizes.
- Task 2: complete; gallery uses populated local examples and real calendar structure; mobile removal focus and leaving-menu accessibility covered.
- Task 3: complete; final 364 unit tests and 282 browser tests passed; build and existing guards passed; 93 preview files verified over HTTP.
- Demo finance: eight table fingerprints unchanged. No unrelated WIP changes; HEAD unchanged; no staging/commit/push.
- Final report: `docs/development/2026-10-20-home-reading-layout.md`.
