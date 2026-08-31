# Production Readiness Gate - 2026-05 baseline and 2026-08-24 status

## Conclusion

This document began as the 2026-05 readiness baseline. Product and test judgments from that snapshot
are historical context, not current-worktree PASS evidence.

Current source verification on 2026-08-24 is complete for the approved local scope: backend normal
and race tests plus `go vet`; Web unit/build/bundle/attachment checks and real-backend Playwright;
Flutter analysis, 404 tests (one designed skip), 48 light/dark screen smokes, and real-backend E2E on
flutter-tester, Android emulator, and iOS simulator; backup/security contracts; current-worktree
Docker image and Compose smokes; strict inventory; and `LOCAL_FINAL_RELEASE=1` all pass. v1.0.9 now
has exact release notes/runbook, current Web/Android/iOS screenshots, a scope-aware Docker/Web source
gate, and a post-publish manifest/runtime gate. GitHub `main`, immutable `v*` tags, `release`, and
`mobile-signing` are protected. The actual v1.0.9 tag, GHCR image, Release, checksum, and published
runtime smoke remain tag-workflow evidence and are not claimed by this pre-tag source record.

## Historical product target

| Requirement | Target State | Current Judgment |
| --- | --- | --- |
| Private/family product model | Single owner account with family members as ledger dimensions, not SaaS multi-tenancy | 2026-05 snapshot; re-review if release scope changes |
| Family functions | Member CRUD, transaction member attribution, family summary, Family Hub UI | 2026-05 snapshot; current regression result not recorded here |
| AI reports | OpenAI-compatible provider, weekly/monthly generation, aggregated snapshot, no raw remarks by default | 2026-05 snapshot; current regression result not recorded here |
| AI secret safety | Provider API keys are omitted from responses/backups and protected at rest | PASS in the 2026-08-24 backend and privacy suites |
| iOS/Android native quality | Flutter native screens, emulator/simulator and accessibility checks | Historical evidence only; current candidate must rerun applicable gates |
| Physical device proof | Real iPhone and Android target-device checks | Current release evidence not recorded |
| Formal distribution | Docker tag workflow plus optional signed Android/iOS attachment workflow | Structure verified; signed/public artifacts not produced for the current local scope |
| Recovery | Backup scope and restore rehearsal | Historical evidence only; rerun for a new strict candidate |

## Release Gate Matrix

| Gate | Required Evidence | Status | Command / Artifact |
| --- | --- | --- | --- |
| Backend regression | All backend unit/integration-safe tests pass | PASS 2026-08-24; normal, race, and vet | `cd backend && go test ./... && go test -race ./... -count=1 && go vet ./...` |
| Web quality gate | Web tests, deferred-attachment contract, production build, budgets, and real-backend browser flow pass with pnpm only | PASS 2026-08-24; 60 tests, 2 Playwright flows | `cd web && pnpm install --frozen-lockfile && pnpm test && pnpm build && pnpm verify:bundle && pnpm verify:attachments`; `./scripts/verify-web-e2e.sh` |
| Mobile static gate | Flutter analyzer and widget tests pass | PASS 2026-08-24; 404 pass, 1 designed skip | `cd mobile && flutter analyze && flutter test` |
| Real backend E2E | Mobile app exercises real auth/account/transaction flow | PASS 2026-08-24; flutter-tester, Android emulator, iOS simulator | `RUN_FLUTTER_TESTER_E2E=1 RUN_ANDROID_E2E=1 RUN_IOS_E2E=1 ./scripts/verify-mobile-e2e.sh` |
| Premium screen smoke | Home, Quick Transaction, AI Reports, Family Hub render in light/dark | PASS 2026-08-24; 48 cases | `cd mobile && flutter test -d flutter-tester integration_test/premium_screens_smoke_test.dart` |
| Android release | Signed release APK/AAB built from CI or local secrets | PREPARED, NOT PROVEN | `.github/workflows/android.yml`, `docs/android-release-signing.md`, then Android release workflow evidence |
| iOS release | Archive, TestFlight build, or signed IPA from configured signing identity | PREPARED, NOT PROVEN | `.github/workflows/ios.yml`, `docs/ios-release-signing.md`, then `flutter build ipa --release` evidence |
| Mobile device QA | USB-connected iPhone and Android emulator run smoke or install/manual checklist | PARTIAL; Android emulator and iOS simulator E2E pass, physical iPhone not connected | `REQUIRE_PHYSICAL_IOS=1 REQUIRE_ANDROID_EMULATOR=1 RUN_PHYSICAL_IOS_E2E=1 RUN_ANDROID_E2E=1 ./scripts/check-mobile-device-qa-preflight.sh` |
| Backup rehearsal | Export, restore into isolated database, verify family member, member-linked transaction, and AI report history | VERIFIED BY DEFAULT STRUCTURAL SUITE 2026-08-24 | `./scripts/check-backup-restore-rehearsal.sh` |
| Backup operator drill | Real app/API export and restore workflow has release-candidate evidence | EVIDENCE CONTRACT VERIFIED 2026-08-24; NO NEW DEPLOYED DRILL | `./scripts/check-backup-operator-drill-local.sh`; `STRICT_BACKUP_OPERATOR_DRILL=1 ./scripts/check-backup-operator-drill.sh` |
| Runtime health endpoint | Public health route checks database, schema version, and storage directories without exposing secrets | CONTRACT VERIFIED 2026-08-24; RELEASE RUNTIME NOT RECORDED | `./scripts/check-runtime-health-contract.sh`; `curl -fsS http://127.0.0.1:8080/api/v1/health` |
| AI privacy contract | Provider keys stay out of responses/backups, reports exclude raw remarks, manual and scheduled snapshots can mask member names | VERIFIED 2026-08-24 | `./scripts/check-ai-privacy-contract.sh` |
| AI provider security | Stored keys encrypted, responses omit raw key, backups omit provider secrets | PASS 2026-08-24 in full backend and privacy suites | `cd backend && go test ./...`; `./scripts/check-ai-privacy-contract.sh` |
| Public git safety | No keys, token, private key, env files, or local database artifacts in commit | PASS 2026-08-24 before staging | `./scripts/check-public-git-safety.sh` and `git status --short` |
| Production readiness structure | Release docs, Android/iOS workflows, pnpm-only web lockfiles, backup rehearsal, and public safety scan are present/clean | VERIFIED 2026-08-24; NON-EXPENSIVE MODE | `./scripts/check-production-readiness.sh` |
| Local release rehearsal | Backend, web, mobile, premium smoke, backup rehearsal, safety scan, and real-backend browser/mobile E2E pass from the current working tree | PASS 2026-08-24; component commands and local final gate recorded | See `docs/quality/local-release-rehearsal-2026-05-27.md` |
| Release artifact preflight | Android/iOS signing workflows, release artifact naming, bundle id/team id, and optional signing-secret presence are checkable | PREPARED | `./scripts/check-release-artifacts-preflight.sh`; use `CHECK_SIGNING_SECRETS=1` before release |
| Docker release preflight | One OCI layout, two scans before login, immutable tag check before push, digest/Compose contract | VERIFIED STRUCTURE 2026-08-24 | `./scripts/check-docker-release-preflight.sh` |
| Local Docker smoke | Current worktree can be built into a Docker image and booted with a temporary `/data` mount | PASS 2026-08-24; healthy, UID 10001, metrics auth and persistence pass | `./scripts/check-docker-local-smoke.sh` |
| Local Docker Compose smoke | Current worktree image can boot through Compose with a persistent `/data` mount and JWT/setup guards | PASS 2026-08-24; bound to 127.0.0.1 | `./scripts/check-docker-compose-local-smoke.sh` |
| Docker release evidence | Published manifest and mandatory runtime smoke run between image push and Release creation | PRE-TAG CONTRACT PASS; POST-TAG ENFORCED | `RELEASE_SCOPE=docker-web RELEASE_PHASE=published STRICT_FINAL_RELEASE=1 ./scripts/check-final-release-gates.sh` |
| Release artifact file evidence | Produced APK/AAB/IPA files can be checked for naming, size, zip validity, sidecar checksums, SHA-256 evidence, and strict signature verification | PREPARED, AWAITING REAL ARTIFACTS | `RELEASE_ARTIFACT_DIR=artifacts RELEASE_VERSION=<version> REQUIRE_IOS_ARTIFACT=1 VERIFY_ARTIFACT_SIGNATURES=1 ./scripts/check-release-artifact-files.sh` |
| Release notes candidate | Supported platforms, limitations, upgrade notes, rollback, and verification summary are exact for v1.0.9 | PASS FINAL VALUES | `STRICT_RELEASE_NOTES=1 ./scripts/check-release-notes-candidate.sh` |
| Release change inventory | Worktree changes have a path-by-path review template and forbidden local/generated files are checked | PASS 2026-08-24 in strict mode | `STRICT_RELEASE_SCOPE=1 ./scripts/check-release-change-inventory.sh` |
| Final release runbook | Docker/Web operations are exact for v1.0.9; optional signed-mobile steps retain their separate boundary | PASS FINAL VALUES | `STRICT_FINAL_RELEASE_RUNBOOK=1 ./scripts/check-final-release-runbook.sh` |
| Mobile device QA preflight | Current device list is inspectable, wireless iPhone is distinguished from USB iPhone, Android emulator presence is checkable, and strict mode executes both platform E2E paths | PREPARED | `./scripts/check-mobile-device-qa-preflight.sh`; strict release uses `REQUIRE_PHYSICAL_IOS=1 REQUIRE_ANDROID_EMULATOR=1 RUN_PHYSICAL_IOS_E2E=1 RUN_ANDROID_E2E=1` |
| Accessibility release evidence | Automated premium accessibility baseline passes; VoiceOver/TalkBack manual evidence template and pass criteria are defined | PARTIAL, AWAITING REAL ASSISTIVE-TECH PASS | `docs/quality/accessibility-release-evidence-2026-05-27.md` |
| Final release gate | Docker/Web has source and published phases; signed-mobile retains artifact/device/accessibility requirements | SCOPE-AWARE | `RELEASE_SCOPE=docker-web RELEASE_PHASE=source STRICT_FINAL_RELEASE=1 ./scripts/check-final-release-gates.sh` |
| Local final acceptance gate | Source readiness plus strict local-only proof while external release evidence is deferred | PASS 2026-08-24 | `LOCAL_FINAL_RELEASE=1 ./scripts/check-final-release-gates.sh` |

## Docker/Web Release Completion Definition

v1.0.9 is complete for its declared Docker/Web scope only when all of these are true:

1. The candidate is merged through protected `main`, and `v1.0.9` points to that immutable commit.
2. Web, backend, security, repository-safety, source-contract, and both architecture scans pass.
3. GHCR `1.0.9` resolves to one digest with `linux/amd64` and `linux/arm64`.
4. The published-image runtime gate passes for health, metrics authentication, UID 10001, and persistence.
5. The non-draft GitHub Release contains the digest-pinned Compose and its valid SHA-256 sidecar.
6. An independent download, checksum, digest comparison, and runtime smoke confirm the public assets.

Signed Android/iOS files, physical iPhone execution, and VoiceOver/TalkBack are not hidden gaps in
this definition; they are explicitly outside v1.0.9. If mobile distribution is later approved, use
`RELEASE_SCOPE=signed-mobile STRICT_FINAL_RELEASE=1 ./scripts/check-final-release-gates.sh` and satisfy
the separate signature, artifact, iOS/Android device validation, and accessibility evidence.

## Publication Status and Remaining Acceptance

Updated 2026-08-31: v1.0.9 is publicly available. Independent download and checksum validation
of its Compose pair, both image architecture identities, and an isolated runtime smoke passed.
Historical failed workflow runs remain visible; they are not proof that the public assets are absent.
See [release recovery verification](release-recovery-verification-2026-08-31.md) for exact identities
and the boundary between local repair, public artifact checks, and remote workflow acceptance.

| Priority | Gap | Required Action |
| --- | --- | --- |
| P1 | Recovery automation repair is local, not yet merged or run in GitHub | Review and merge the repair; exercise the complete-release read-only path without replacing v1.0.9 |
| P1 | No fresh target production upgrade/rollback acceptance | Verify on an isolated copy of the installation owner's data before changing production |
| Optional | Production-specific backup drill | Repeat the operator drill against an isolated deployment if the installation owner requires environment-specific evidence |

Use `RUN_EXPENSIVE=1 ./scripts/check-production-readiness.sh` for a fresh local source rehearsal.
The finalized user-facing scope is in
`docs/quality/release-notes-candidate-2026-05-27.md`; historical templates are not retained here.
