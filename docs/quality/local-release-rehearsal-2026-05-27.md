# Local Release Rehearsal - 2026-05-27

## Conclusion

The local release rehearsal entrypoint is `RUN_EXPENSIVE=1 ./scripts/check-production-readiness.sh`. It verifies the current working tree directly, not only `HEAD`, and is the local gate before any tag, artifact upload, or public release.

This rehearsal cannot replace signed Android/iOS artifact generation or physical iPhone validation. It proves source-level release readiness on the local machine.

Latest local final gate run on 2026-05-30: **PASS**.

## Covered Gates

| Area | Command | Purpose |
| --- | --- | --- |
| Public safety | `./scripts/check-public-git-safety.sh` | Detect private keys, common API keys, local credentials, and public repo hazards |
| Backup recovery | `./scripts/check-backup-restore-rehearsal.sh` | Prove family member, member-linked transaction, and AI report history survive backup/restore |
| Backup operator drill structure | `./scripts/check-backup-operator-drill.sh` | Prove the real export/restore operator evidence template exists and is checkable |
| Release artifact preflight | `./scripts/check-release-artifacts-preflight.sh` | Prove Android/iOS workflows, tag release artifact attachment paths, and signing-secret checks are wired |
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

## Latest Evidence

| Gate | Result |
| --- | --- |
| Backup recovery | PASS |
| Backup operator drill structure | PASS |
| Release artifact preflight | PASS, includes Android APK/AAB, iOS IPA, checksums, and tag release attachment paths |
| Release notes candidate | PASS |
| Release change inventory | PASS |
| Final release runbook | PASS |
| Local Docker smoke | PASS, built `personal-ledger:local-smoke` and served HTTP on a temporary localhost port |
| Local Docker Compose smoke | PASS, built `personal-ledger:local-smoke`, served HTTP on a temporary localhost port, verified image healthcheck, JWT guard, and persistent `ledger.db` / `uploads` / `backups` |
| Backend `go test ./...` | PASS |
| Web `pnpm install --frozen-lockfile && pnpm run build` | PASS |
| Flutter analyze | PASS |
| Flutter tests | PASS, 192 tests |
| Premium screen smoke | PASS, 8 light/dark cases |
| Real backend mobile E2E | PASS on flutter-tester |
| Local final release gate | PASS on 2026-05-30; `LOCAL_FINAL_RELEASE=1 ./scripts/check-final-release-gates.sh` completed runtime health, AI privacy, production readiness, strict release inventory, strict backup operator drill, Docker local image smoke, Docker local compose smoke, and whitespace checks |
| Local Docker image smoke | PASS on 2026-05-30; built `personal-ledger:local-smoke`, healthcheck `healthy`, latest temporary localhost port `32779`, persistent `ledger.db` / `uploads` / `backups` verified |
| Local Docker Compose smoke | PASS on 2026-05-30; built `personal-ledger:local-smoke`, healthcheck `healthy`, latest temporary localhost port `63896`, JWT guard PASS, persistent `ledger.db` / `uploads` / `backups` verified |
| Strict final release gate | FAIL expected on 2026-05-30; missing real signed APK/AAB/IPA or TestFlight/archive evidence, GHCR digest/multi-arch manifest, USB iPhone physical QA, manual VoiceOver/TalkBack evidence, final release notes/runbook values, and artifact files |

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
| Physical iPhone validation | Requires USB-connected device or supported physical-device workflow |
| Real screen-reader pass | Requires manual VoiceOver/TalkBack operation on target device |
