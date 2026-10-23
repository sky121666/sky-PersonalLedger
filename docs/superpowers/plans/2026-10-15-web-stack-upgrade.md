# Web Stack Upgrade Implementation Plan

> Execute inline with `superpowers:executing-plans`. Keep all pre-existing
> changes. Do not stage, commit, push, tag, or deploy.

**Goal:** Upgrade the Web stack to the reviewed stable versions, fix
compatibility, and verify the application against an isolated backend.

**Architecture:** Keep the Vue SPA and Go API boundary. Use Tailwind's Vite
integration, preserve the existing visual design and class-based dark mode,
and retain TypeScript 6.0.3 for Vue compiler API compatibility.

**Tech Stack:** Node 26.12.0, pnpm 12.11.2, Vue 3.5.44, Router 5.4.0,
Pinia 4.1.0, Vite 8.3.4, Tailwind 4.3.3, TypeScript 6.0.3,
vue-tsc 3.3.13, Vitest 5.0.4, Playwright 1.64.1.

**Spec:** The user-approved proposal in this chat on 2026-10-15, including
the TypeScript exception, Tailwind browser baseline, Web CI/Docker changes,
isolated test configuration, and preservation of pending work.

## Constraints and recovery

- Safari 16.4+, Chrome 111+, Firefox 128+ are the accepted CSS baseline.
- No new UI framework, server-state library, backend API, or database schema.
- Use temporary synthetic databases and task-owned services for verification.
- Update only the frontend build stage in Docker; preserve backend/runtime pins.
- Preserve all 70 pre-existing modified/untracked files. The starting diff,
  original file copies and hashes are in the task's external evidence directory.
- Work in the existing checkout to include the pending business fixes in the
  validation baseline. Restore only this task's changes if recovery is needed.
- Keep one progress record here rather than creating another tracking system.

## Review focus

- Tailwind layers must not erase padding, margins, theme colors or dark mode.
- Real Vue components must retain focus, events, Teleport and cleanup behavior.
- Router/Pinia startup and session recovery must not expose stale account data.
- Cookie, multipart and Blob requests must still work in real browsers.
- CI, local builds and Docker must resolve the same versions without stale
  security overrides, missing native packages or weakened verification gates.

## Task 1: Baseline and toolchain

- [x] Save the initial diff and hashes outside the repository.
- [x] Run existing Web tests/build and preserve baseline output.
- [x] Obtain task-local Node 26.12.0 and pnpm 12.11.2 without changing global tools.
- [x] Update `.node-version`, Web engines/package manager, Web CI, Docker's
  frontend builder and the toolchain consistency check.
- [x] Verify exact runtime versions and frozen installation.

## Task 2: Dependencies and compiler compatibility

- [x] Upgrade retained direct dependencies to the reviewed stable releases.
- [x] Add Pinia's required devtools peer dependency.
- [x] Remove unused Vant/automatic-component configuration only after confirming
  imports and a passing production build.
- [x] Adapt TypeScript 6 configs and Vitest 5 tests without weakening assertions.
- [x] Resolve overrides/patches against the actual new dependency graph.
- [x] Run all Web unit tests, type checks and production build.

## Task 3: Tailwind and browser regression coverage

- [x] Establish controlled visual/geometry and dark-mode expectations.
- [x] Migrate theme values, dark variant, reset layers and utility differences.
- [x] Add real-component/browser coverage for the upgrade's concrete risks.
- [x] Verify desktop/mobile and explicit light/dark preferences in Chromium,
  Firefox and WebKit where supported by the local test runtime.
- [x] Preserve visual evidence and inspect representative screenshots.

## Task 4: Complete verification and review

- [x] Frozen install; dependency/peer checks and production/full security audit.
- [x] Full Web unit suite, production build, attachment guard and bundle budget.
- [x] Full real-backend browser suite using an isolated temporary database.
- [x] Toolchain, version, public-Git-safety and whitespace checks.
- [x] Build and smoke-test the Docker image without production services.
- [x] Independent review of this task's delta; fix material findings and rerun
  affected checks.
- [x] Compare preserved pending files against baseline; report exact results,
  remaining limits, and confirm no staging/commit/push.

## Execution evidence

- Baseline evidence directory:
  `/var/folders/l6/smy8mmk15898tpm0vddrbyt00000gn/T/ledger-web-upgrade-20261015-wnrahk9f`.
- Initial staged diff: empty. Pre-existing modified/untracked files: 70.
- Baseline declared Node: 24.18.1; default terminal Node: 22.23.1.
  Baseline verification uses the available Node 24.21.0, which satisfies the
  existing manifest; target verification will use the exact new runtime.

## Compatibility decisions and current verification

- The registry marked `lucide-vue-next@1.0.0` deprecated. Retained the Lucide
  library and migrated imports to its maintained `@lucide/vue@1.57.0` package.
- Tailwind uses explicit application sources, a class dark variant, and inline
  legacy design tokens. Fixed reset layers, inline form-label spacing, sRGB
  gradients, multiple drop shadows, transparent outlines and disabled cursors.
- Removed unused Vant/component auto-import tooling and generated declarations.
  The new dependency graph contains no braces; the existing gate now rejects
  its return anywhere in the lockfile. Two malicious graph probes confirm this.
- Node/application/test types are separated. TypeScript 6 requires an explicit
  ArrayBuffer-backed typed-array annotation in one existing test fixture.
- pnpm 12's release-age exceptions are exact versions selected for this upgrade,
  not wildcard package exemptions. Production and full audits both report zero
  known vulnerabilities. Frozen install with strict peers passes.
- The original 176 unit tests pass. Eight Chromium screenshots match the old
  desktop/mobile light/dark baseline within the original 1% pixel threshold.
- WebKit mouse clicks do not focus buttons. Focus-restoration tests now open
  dialogs by keyboard from an explicitly focused trigger; restoration and
  focus-trap assertions remain intact. The final cross-browser run passes all
  60 tests (20 each in Chromium, Firefox and WebKit).
- Bundle budgets remain unchanged: largest CSS 107435 bytes (limit 120000);
  largest JavaScript 181387 bytes (limit 200000). Total compressed assets are
  223289 bytes versus 219174 at baseline (+4115 bytes, approximately 1.9%).
- Docker native arm64 build and isolated smoke pass: healthy image, runtime UID
  10001, metrics authorization, SQLite and persistent upload/backup paths.
- Actionlint, CI action pinning, Docker/release preflights and version/toolchain
  checks pass. Three negative toolchain-drift probes reject inconsistent pins.
- Pending work is checked against the original 70-file manifest. Overlapping
  changes are limited to Lucide imports, typed-array annotation and outline class migration and keyboard
  setup in the cross-browser test; no business logic is replaced.

## Final review and acceptance details

- Two independent reviews and a targeted follow-up identified CSS issues and
  a probe expectation error. Applied fixes and verified actual browser output.
- Form-label compatibility excludes existing flex layouts. Standard Tailwind
  `outline-hidden` classes cover ordinary, focus and peer-focus cases. Forced
  colors are verified in Chromium/Firefox; WebKit verifies normal-mode behavior
  because Playwright cannot emulate forced colors there.
- The new CSS probe verifies compiled multiple drop shadows, sRGB gradients,
  disabled cursor, flex permission labels and focus outlines. Normal outline
  style `none` is tested independently of its irrelevant computed width.
- Node test workers, browser contexts and the isolated backend all use
  Asia/Shanghai. The explicit process environment also covers direct Playwright
  invocations and avoids UTC month-boundary differences in CI.
- Final verification: 176 unit tests, 60 browser E2E tests, 6 targeted Chromium
  compatibility tests including eight old-stack screenshot comparisons, full
  application/test type checks, production build, Vite development smoke, both
  dependency audits, all unchanged bundle budgets, attachment/brace guards,
  workflow lint/pinning, release preflights and repository safety checks pass.
- The 70 pre-existing dirty files are preserved. 54 are byte-identical; the
  remaining 16 normalize exactly to their saved SHA-256 after reversing only
  this task's import/class/type/keyboard-test compatibility edits.
- HEAD matches the saved baseline and the index is empty. No staging, commit,
  push, tag or deployment was performed.
- Local validation used task-local Node 26.12.0 and pnpm 12.11.2; the user's
  global/default Node 22.23.1 was not changed. Development requires selecting
  the project-pinned runtime.
- Remote GitHub CI, actual minimum-version browsers and physical mobile devices
  were not run. Current Playwright engines and native arm64 Docker smoke were
  exercised locally. The amd64 frontend build also passes frozen installation, both type checks
  and Vite production compilation under local emulation. The complete amd64
  backend/runtime image was not exercised.

- Final local acceptance is complete. The native arm64 full image is
  `personal-ledger:web-stack-20261015`; the amd64 frontend-only validation image
  is `personal-ledger:web-stack-amd64-20261015`. Neither image was pushed.

## Populated Web walkthrough acceptance, 2026-10-15

Scope: all 18 route entries, including setup/login and the 16 authenticated
entries, using synthetic data only. Existing uncommitted work is retained.
No production data, staging, commit, push, tag or deployment is included.

| Area | Exercised operations |
| --- | --- |
| Setup and login | Fresh tmpfs-backed initialization, database/advanced forms, invalid confirmation, password changes on phone/desktop, login and logout |
| Home and transactions | Populated summaries, list/calendar, transaction CRUD, long notes, transfer balances, filtering, account-specific/all-account logs, actual CSV download |
| Statistics, reports and budgets | Month and income/expense selection, annual report and annual CSV, total/category/member budget create/edit/reopen verification |
| Management | Account create/edit/archive/restore/delete, category and tag CRUD, template create/apply/delete, family member create/edit/disable |
| Debts and lending | Create/edit/pause/enable, real repayment balance changes, due-date create/preserve/clear, settled records and uncertain-response recovery |
| Settings | Profile/theme persistence, notification tabs and disabled-channel save, password, security-path draft, token create/revoke, import preview/commit/rollback, downloaded backup restore and automatic backup |
| AI | Real isolated Provider CRUD and schedule persistence; report generation/history/deletion and connection response rendered with explicit browser fixtures; manual schedule trigger with no enabled Providers and zero failed runs |

### Repairs

- Account cards keep their name and four accessible 44px actions readable.
  Explicit card width and intermediate grid breakpoints eliminate overflow at
  320, 390, 768, 820, 900 and 1440px. Hover transforms respect touch input and
  reduced-motion settings.
- Category inputs and icon grids fit short phones. Debt type labels remain
  horizontal. Repayment, profile, password and security panels scroll within
  the available viewport. AI/family refresh buttons remain on one line.
- Account-log routes select the management navigation. AI Provider/report
  actions have accessible names and at least 44px touch targets.
- Settings displays the full transaction total, including 176 synthetic
  visible transactions, rather than the current month's 42.
- Lending creation/repayment uses explicit instants. Both create and edit
  normalize a nonempty due date; clearing an existing date sends explicit null.
- Import history, preview, selection and validation ignore obsolete requests,
  including obsolete errors/finally blocks. Commit/rollback block file changes
  and duplicate operations until their write completes.
- Lending accepts the legacy minute-precision local datetime in old pending
  repayments without rewriting the raw request or its idempotency key.
  Tests verify one account debit, one repayment record and one transaction
  after replay, and conflict rejection if that key is reused with changed data.

### Verification and isolation

- Evidence directory:
  `/var/folders/l6/smy8mmk15898tpm0vddrbyt00000gn/T/ledger-web-allpages-20261015-zygxzt_v`.
- `pnpm --dir web test`: 188 tests pass in 21 files. Both application and test
  type checks and the production build pass.
- `go test ./...`: all backend packages pass, including the legacy repayment
  compatibility regression.
- `scripts/verify-web-e2e.sh`: 183 tests pass across Chromium, Firefox and
  WebKit. After tightening the AI test's external-call boundary, the 12 affected
  analysis tests pass again on all three engines, with report screenshots.
  Manual schedule trigger is forced by the backend even when automation is
  disabled; the test therefore removes its Provider before triggering and
  verifies that every attempted run is skipped without failure.
- Final populated preview scans cover 16 authenticated entries x 2 themes x
  2 viewports (1440/390): all 64 states have no page/main horizontal overflow
  and no error alerts. Separate 320x568 and intermediate-width probes cover
  short dialogs, visible actions, inputs and account-card geometry.
- Brace/attachment guards, toolchain consistency, unchanged bundle budgets and
  whitespace checks pass. The runtime remains Node 26.12.0 / pnpm 12.11.2,
  with the accepted TypeScript 6.0.3 exception and Tailwind v4 browser baseline.
- Subsequent local environment setup supersedes the earlier upgrade-only
  runtime note: the default interactive login shell now reports Node 26.12.0
  and pnpm 12.11.2, verified again during this walkthrough.
- Independent read-only reviews identified the due-date, import-race, legacy
  pending-request and test-isolation gaps; each received a targeted repair
  and regression evidence.

The preview refresh exposed intermittent SQLite I/O failures on the macOS
virtiofs bind mount: 34 failures in 80 parallel read requests. A stopped,
integrity-checked copy on a task-specific Docker native volume passes the same
eight-endpoint workload with 160/160 reads, without application/database-pool
workarounds. The comparison identifies the local storage boundary; the exact
virtiofs failure mechanism is not established.

- Preview: `http://127.0.0.1:5173`; isolated API: `127.0.0.1:8080`.
- Current image: `personal-ledger:web-allpages-20261015`.
- Current container: `ledger-web-preview-20261015`.
- Current isolated data volume: `ledger-web-preview-data-20261015-allpages`.
- Preserved source directory:
  `/var/folders/l6/smy8mmk15898tpm0vddrbyt00000gn/T/ledger-local-dev-20261015-4dedt4ry/backend-data`.
- Preserved stopped containers:
  `ledger-web-preview-before-allpages-20261015` and
  `ledger-web-preview-bind-allpages-20261015`.
- Visible transactions remain 176; the physical table has 178 rows because
  two existing `system` entries are excluded from the normal transaction list.
- Never open the live container SQLite database from the host for inspection;
  use application APIs/backups or inspect a stopped copy.
- The temporary tmpfs setup/password-check service is stopped. The populated
  preview remains running, with its light-theme desktop homepage retained.
- Final preservation audit: all 862 baseline files still exist; 848 are
  byte-identical. The 14 scoped changed files have saved originals whose
  SHA-256 values match the baseline. Three new E2E files were added. HEAD
  matches the saved baseline and the index remains empty.

Limitations: physical mobile devices, the oldest supported browser versions,
real external AI services and outbound notification delivery are not verified
by these local browser fixtures. Database connection forms were inspected
without connecting to any remote PostgreSQL/MySQL service.


## 2026-10-15 final dependency and infrastructure follow-up

Authorized scope: refresh compatible transitive dependencies, Web/release CI Actions,
Docker base/build tools, and non-interactive Node/pnpm selection. Preserve all existing
WIP, TypeScript 6.0.3, the Tailwind browser baseline and upstream exact dependencies.
Do not access production data, stage, commit, push or publish.

- [x] Save the pre-task worktree and local shell configuration outside the repository.
- [x] Refresh the lockfile within upstream ranges, with exact release-age exceptions.
- [x] Verify release SHAs/action input schemas; update shared actions consistently.
- [x] Pin Go 1.26.9, Alpine 3.24.2, BuildKit 0.34.0 and the current Skopeo digest.
- [x] Fix project-scoped non-interactive zsh selection and add runtime gate regression tests.
- [x] Strict frozen install, application/test types, 188 unit tests, bundle budgets and audits.
- [x] Complete the final Go and three-engine browser rerun after the x/net security fix.
- [x] Build both Docker architectures with the pinned BuildKit and verify isolated runtime/OCI handoff.
- [x] Independent review and final WIP/index/HEAD preservation check.

Ruling: Go stays on the existing 1.26 branch and receives its latest patch (1.26.9);
the 1.27 feature-line migration is outside this Web follow-up. Static consistency checks
remain usable by Go-only release jobs; Web CI explicitly enables --runtime validation.

Validation so far: new shell processes started with an intentionally stale PATH select
26.12.0/12.11.2 in both repository root and web/, for zsh -c, -lc and -lic;
non-project non-interactive shells retain their previous selection. Four runtime gate
regressions pass. Action input validation covers 57 uses; actionlint and immutable pinning,
release preflights, 30 release-contract tests and four persistence-probe tests pass.
The independent read-only reviewer found no actionable issue in this follow-up diff.
The first Docker build hit a transient Alpine CDN TLS error; the retry retains TLS validation
and uses checksum-verified Buildx 0.38.0 with BuildKit 0.34.0.

The runtime vulnerability gate found GO-2026-6611 / CVE-2026-78669 in
golang.org/x/net v0.57.0 (Gin imports its HTTP/2 implementation). The official
fix v0.60.0 requires Go 1.26.0 and is compatible with the selected Go 1.26.9.
Ruling: update this transitive module, the x/* versions required by its module graph, and checksums; then rerun the backend,
browser integration and both image builds/scans; do not add a vulnerability ignore.
The first successful OCI build/smoke remains historical evidence until this rerun completes.

### Final follow-up verification

- Evidence directory:
  `/var/folders/l6/smy8mmk15898tpm0vddrbyt00000gn/T/ledger-upgrade-finish-t3q2fu6g`.
- After the x/net update, all 846 Go tests in 15 packages pass. The final Web
  run passes 188 unit tests, application/test type checks, production build,
  bundle budgets, attachment/brace guards and strict dependency installation.
  Production and full dependency audits report no known vulnerabilities.
- Final isolated E2E: 189/189 pass across Chromium, Firefox and WebKit in
  5.8 minutes, including desktop/mobile management flows and six new toast
  interaction cases.
- Independent review rejected an interim test-only wait for toast expiry.
  A deterministic hit-test regression reproduces the actual mobile interception:
  stacked toast content covers a dialog close button. Toast content now lets
  pointer events through; its dismiss button remains interactive. The test
  closes the dialog while both notices remain present, then dismisses a notice.
  The old code fails this regression; the final code passes all six browser/size
  cases and the full suite. The interim expiry wait has been removed.
- Final arm64/amd64 OCI digest:
  `sha256:69b73807fcfd83a2c3503a092148982d7e220aa9ce20bcccb5f77ab39bebd559`.
  Both archives pass architecture checks and isolated Docker runtime smoke;
  Trivy 0.76.0 finds zero fixable HIGH/CRITICAL vulnerabilities using the
  2026-10-15 database. OCI archive/restore retains the same image digest.
- A local amd64 emulation attempt stalled in CGO with an unreaped gcc child;
  the same build parameters succeeded on retry. No source workaround or
  compiler/security downgrade was introduced. Final images include the toast fix.
- GitHub action schemas, actionlint, immutable pins, release preflights,
  30 release-contract tests, four persistence-probe tests and four runtime
  selection tests pass. The optional Forgejo checkout mirror is also updated
  to the verified v7.0.1 commit; its self-hosted executor needs Node 24 support.
- All pre-task files are preserved; originals of changed files remain in the
  evidence backup. HEAD and the index are unchanged. Local shell changes are
  confined to new project-scoped `.zshenv` / `.zlogin` hooks; `.zshrc` and
  `.zprofile` are byte-identical to their saved originals.

Remote GitHub/Forgejo workflow execution, the actual self-hosted runner,
physical devices and the oldest supported browser versions are not verified
by these local checks. No production data, staging, commits, pushes or
publication were involved.
