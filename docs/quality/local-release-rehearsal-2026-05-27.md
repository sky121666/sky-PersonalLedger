# Local Release Rehearsal - 2026-05 historical record and 2026-08-24 status

## Conclusion

The local release rehearsal entrypoint is `RUN_EXPENSIVE=1 ./scripts/check-production-readiness.sh`.
It verifies the working tree present when the command is run, not only `HEAD`.

The results originally recorded in this file belong to the 2026-05 tree. They are retained only as
historical context and must not be used as PASS evidence for the current candidate.

Current status on 2026-08-24: the release and artifact structure, immutable Action pins,
release-version safety, backend normal/race/vet, Web unit/build/budget/attachment and Playwright,
Flutter analyzer/unit/widget/screen-smoke, three-target mobile real-backend E2E, backup/security
contracts, current-worktree Docker image and Compose smokes, strict inventory, and
`LOCAL_FINAL_RELEASE=1` all pass. External publication, signed artifacts, physical iPhone, and
manual screen-reader evidence were intentionally not claimed.

## Covered Gates

| Area | Command | Purpose |
| --- | --- | --- |
| Public safety | `./scripts/check-public-git-safety.sh` | Detect private keys, common API keys, local credentials, and public repo hazards |
| Backup recovery | `./scripts/check-backup-restore-rehearsal.sh` | Prove family member, member-linked transaction, and AI report history survive backup/restore |
| Backup operator drill structure | `./scripts/check-backup-operator-drill.sh` | Prove the real export/restore operator evidence template exists and is checkable |
| Release artifact preflight | `./scripts/check-release-artifacts-preflight.sh` | Prove Android/iOS workflows, manual signed-release attachment paths, and signing-secret checks are wired |
| Release notes candidate | `./scripts/check-release-notes-candidate.sh` | Prove supported platforms, limitations, upgrade notes, rollback, and verification sections exist |
| Release change inventory | `./scripts/check-release-change-inventory.sh` | Prove the working tree scope is categorized and forbidden local/generated files are not in status |
| Final release runbook | `./scripts/check-final-release-runbook.sh` | Prove the ordered final release operation path exists |
| Local Docker smoke | `./scripts/check-docker-local-smoke.sh` | Prove the current worktree Dockerfile can build and boot with a temporary `/data` mount |
| Local Docker Compose smoke | `./scripts/check-docker-compose-local-smoke.sh` | Prove the current worktree image can boot through Compose with a persistent `/data` mount and JWT secret guard |
| Backend | `cd backend && go test ./...` | Run backend regression tests |
| Web | `cd web && pnpm install --frozen-lockfile && pnpm run build` | Prove pnpm lockfile and production web build |
| Mobile static | `cd mobile && flutter analyze && flutter test` | Prove Flutter analyzer and widget/unit tests |
| Premium mobile smoke | `cd mobile && flutter test integration_test/premium_screens_smoke_test.dart` | Prove premium Home, Quick Transaction, AI Reports, and Family Hub render in light/dark |
| Real backend mobile E2E | `./scripts/verify-mobile-e2e.sh` | Prove mobile auth/account/transaction flow against a real local backend |
| Local final release gate | `LOCAL_FINAL_RELEASE=1 ./scripts/check-final-release-gates.sh` | Prove strict local source, Docker, backup, inventory, and whitespace gates while external release evidence is intentionally deferred |

## Historical evidence boundary

The 2026-05-30 rehearsal covered backend, Web, Flutter, backup, local Docker/Compose, and local final
gate paths for the tree that existed on that date. Port numbers, test counts, and PASS rows from that
run were removed because they are not reusable evidence after the current release and application
changes. Re-run the commands below to create evidence for a new candidate.

## Current verification - 2026-08-24

| Gate | Current result |
| --- | --- |
| Docker release structural preflight | VERIFIED; build/scan/login/tag-check/push ordering and Compose contract |
| Release artifact structural preflight | VERIFIED; workflow and attachment contracts only |
| GitHub/Forgejo Action pinning | VERIFIED |
| Release version safety tests | VERIFIED |
| Backend | PASS; `go test ./...`, `go test -race ./... -count=1`, `go vet ./...` |
| Backend targeted soak | PASS; restore/attachment/credential/notification/evidence tests repeated 10 times |
| Web | PASS; 60 unit tests, production build/budgets/attachment contract, 2 real-backend Playwright flows |
| Flutter static/unit | PASS; analyzer clean, 404 tests pass with 1 designed skip |
| Premium screen smoke | PASS; 48 light/dark cases |
| Mobile real-backend E2E | PASS; flutter-tester, Android emulator, iOS simulator |
| Default production-readiness structural suite | VERIFIED |
| Current-worktree Docker image smoke | PASS; health, UID 10001, metrics auth, persistence |
| Current-worktree Docker Compose smoke | PASS; JWT/setup guards, health, UID 10001, metrics auth, persistence |
| Local final release gate | PASS; external evidence intentionally skipped |
| Published current-candidate image and release-image smoke | NOT RUN; no tag or publication was performed |

## Command

Run from the repository root:

```bash
RUN_EXPENSIVE=1 ./scripts/check-production-readiness.sh
```

For the current local final acceptance scope, run:

```bash
LOCAL_FINAL_RELEASE=1 ./scripts/check-final-release-gates.sh
```

## Pass Criteria

- All commands finish with exit code 0.
- `git diff --check` passes after any generated-file cleanup.
- `git status --short` contains only intentional release changes.
- No Android emulator, Flutter test, Gradle, or Go test process is left running.

## Not Covered

| Gap | Why |
| --- | --- |
| Signed Android artifact | Requires release keystore secrets or CI artifact run |
| Signed iOS IPA/TestFlight | Requires Apple certificate, provisioning profile, and export options |
| iOS/Android device QA | Current candidate requires USB-connected iPhone plus Android emulator E2E or supported signed-install manual workflow |
| Real screen-reader pass | Requires manual VoiceOver/TalkBack operation on target device |
