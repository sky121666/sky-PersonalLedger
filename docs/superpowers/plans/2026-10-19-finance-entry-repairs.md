# Financial Entry Reliability Implementation Plan

**Goal:** Repair the five confirmed audit findings without changing historical balances or the current design system.

**Architecture:** Reuse existing transaction boundaries, request journals, import deduplication, component tests and isolated browser fixtures. Ordinary transaction idempotency is optional for older clients. A request identity represents one intent, never a content-based duplicate heuristic.

**Constraints:** Preserve all existing WIP. No production data, historical recalculation, dependency changes, commits, staging or pushes. Build and run tests only in the isolated source copy.

## Tasks

- [x] Add failing ordinary transaction retry tests, including conflicting payloads, separate equal transactions, deletion, rollback and backup/restore. Reuse the existing request-claim storage with an explicit operation and transaction reference; do not add a schema migration.
- [x] Add an optional request key to ordinary creation. Bind a stable transaction identity to the request, claim and write atomically, and return the existing transaction on retry. Reject conflicting or deleted requests without balance changes.
- [x] Make the Web transaction dialog retain the exact uncertain request, reuse its key on retry and recover it on reopening. Isolate browser journals by authenticated user and backend. Keep edit semantics unchanged.
- [x] Reproduce rollback/reimport divergence. Keep historical fingerprint reservations and make import preview/submission agree without changing deleted transactions or balances.
- [x] Correct the homepage reminder progress scope and destination; keep mixed debt aggregation deferred.
- [x] Make lending principal/date read-only when editing, with creation behavior unchanged.
- [x] Preserve successful uploads across per-file failures and prevent concurrent batches from losing paths or exceeding limits.
- [x] Run the Web unit suite, type check/build, Go suite and targeted race checks in isolation. Run current desktop/mobile browser workflows using synthetic fixtures.
- [x] Review the cumulative task patch against the pre-task manifest, then copy only the reviewed files back. Verify that unrelated WIP remains byte-for-byte intact.

## Review Focus

- Lost creation responses must not create a second transaction.
- A changed payload under the same key must fail before money moves.
- Deletion, account archival and backup restore must not resurrect a previous write.
- Restoring or retrying a journal under another user/backend must not disclose or replay its contents.
- Partial attachment failures must retain earlier successes and expose a usable retry.

## Verification Evidence

Record red/green outcomes and final suite results in the isolated run directory. Historical audit results are context, not proof that the current patch passes.

## Additional Findings Resolved During Acceptance

- Full-suite data exposed an existing Firefox SIGSEGV when a conic gradient contained 1,209 sectors. Original and updated frontends failed with the same synthetic response; a single-div probe reproduced it. Compressing adjacent identical colors preserves every category row, amount and sector boundary. The original eight failing statistics cases and new 1,280-category cases now pass. Arbitrarily many distinct-color sectors are outside this verified bound.
- Interest projection creation incorrectly included a newly generated category ID in the FirstOrCreate lookup. New IDs now belong to Attrs, so later interest entries reuse an available category matching the original user/type/name criteria. Existing duplicate categories and historical transaction category references are retained, with a dedicated regression proving this.
- The CRUD fixture now uses an explicit later occurrence time so second-precision debt fixtures cannot displace it from the homepage's latest 20 rows. No application sorting or transaction date rules changed.
- Independent review found and drove fixes for late-success journal clearing, confirmation recovery, upload/save overlap and the current-read path for server database retries.

## Final Verification

- Go full suite: 1,086 passing test/subtest events; 11 external MySQL/PostgreSQL integration cases skipped because no instances were configured.
- Targeted Go race checks passed for manual transaction retries, HTTP retry contracts, import behavior and interest-category reuse.
- Web: 31 unit-test files, 273 tests; type checks, production build, attachment contract, parser guard and bundle budgets passed.
- Browser full suite: 324 passed across Chromium, Firefox and WebKit, using the retained synthetic ledger and desktop/mobile sizes. No retries or skipped cases in this final run.
- Cross-user backup restore, deleted-transaction restore and archived-account confirmation retained request protection in isolated databases.

## Compatibility Boundaries

- Request keys are optional for old clients. The current Web ordinary-create dialog sends and preserves them; template application and other creation endpoints retain their existing contracts.
- Imported soft-deleted fingerprints remain reserved. Reimport skips them; this patch does not resurrect rolled-back records.
- Old backups remain readable. Backups carrying the new transaction request operation require the patched restore guard; an older guard rejects that operation. No request evidence is dropped for rollback compatibility.
- The user-approved TypeScript exception, Tailwind browser baseline, dependency versions, CI and Docker files are unchanged. No production data, historical balances or schema were changed.
