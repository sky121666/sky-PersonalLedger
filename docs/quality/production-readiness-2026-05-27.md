# Production Readiness Gate - 2026-05 baseline and 2026-08-24 status

## Conclusion

This document began as the 2026-05 readiness baseline. Product and test judgments from that snapshot
are historical context, not current-worktree PASS evidence.

Current source verification on 2026-08-24 is complete for the approved local scope: backend normal
and race tests plus `go vet`; Web unit/build/bundle/attachment checks and real-backend Playwright;
Flutter analysis, 404 tests (one designed skip), 48 light/dark screen smokes, and real-backend E2E on
flutter-tester, Android emulator, and iOS simulator; backup/security contracts; current-worktree
Docker image and Compose smokes; strict inventory; and `LOCAL_FINAL_RELEASE=1` all pass. No signed
mobile artifact, physical iPhone pass, new GHCR tag, GitHub Release, or published-image deployment
smoke was produced, so external release evidence remains pending.

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
| Docker release evidence | Published image manifest and optional compose smoke can be checked after tag release | PREPARED, AWAITING REAL IMAGE | `DOCKER_RELEASE_IMAGE=ghcr.io/<owner>/<repo>:<version> ./scripts/check-docker-release-evidence.sh` |
| Release artifact file evidence | Produced APK/AAB/IPA files can be checked for naming, size, zip validity, sidecar checksums, SHA-256 evidence, and strict signature verification | PREPARED, AWAITING REAL ARTIFACTS | `RELEASE_ARTIFACT_DIR=artifacts RELEASE_VERSION=<version> REQUIRE_IOS_ARTIFACT=1 VERIFY_ARTIFACT_SIGNATURES=1 ./scripts/check-release-artifact-files.sh` |
| Release notes candidate | Supported platforms, limitations, upgrade notes, rollback, and verification summary are checkable | PREPARED, AWAITING FINAL VALUES | `./scripts/check-release-notes-candidate.sh`; use `STRICT_RELEASE_NOTES=1` before release |
| Release change inventory | Worktree changes have a path-by-path review template and forbidden local/generated files are checked | PASS 2026-08-24 in strict mode | `STRICT_RELEASE_SCOPE=1 ./scripts/check-release-change-inventory.sh` |
| Final release runbook | Signing, tag release, artifact verification, physical QA, backup drill, accessibility, release notes, and final gate are ordered | PREPARED, AWAITING FINAL VALUES | `./scripts/check-final-release-runbook.sh`; use `STRICT_FINAL_RELEASE_RUNBOOK=1` before release |
| Mobile device QA preflight | Current device list is inspectable, wireless iPhone is distinguished from USB iPhone, Android emulator presence is checkable, and strict mode executes both platform E2E paths | PREPARED | `./scripts/check-mobile-device-qa-preflight.sh`; strict release uses `REQUIRE_PHYSICAL_IOS=1 REQUIRE_ANDROID_EMULATOR=1 RUN_PHYSICAL_IOS_E2E=1 RUN_ANDROID_E2E=1` |
| Accessibility release evidence | Automated premium accessibility baseline passes; VoiceOver/TalkBack manual evidence template and pass criteria are defined | PARTIAL, AWAITING REAL ASSISTIVE-TECH PASS | `docs/quality/accessibility-release-evidence-2026-05-27.md` |
| Final release gate | Structural readiness plus optional strict final proof for clean worktree, artifacts, iOS/Android device QA, and accessibility evidence | PREPARED | `./scripts/check-final-release-gates.sh`; use `STRICT_FINAL_RELEASE=1` only for a real release candidate |
| Local final acceptance gate | Source readiness plus strict local-only proof while external release evidence is deferred | PASS 2026-08-24 | `LOCAL_FINAL_RELEASE=1 ./scripts/check-final-release-gates.sh` |

## 100/100 Definition

The project can be called 100/100 for the current product goal only when all of these are true:

1. Backend, web, mobile, and real-backend E2E gates pass from the current worktree.
2. Android release artifact is signed and attached to a release or preserved as a CI artifact.
3. iOS has either a successful physical-device run or a signed archive/TestFlight build.
4. Backup/restore is rehearsed with a family member, member-linked transaction, and AI report history present.
5. AI provider keys are verified to stay out of API responses, normal backups, logs, and git output.
6. Release notes list supported platforms, known limitations, upgrade notes, and rollback path.
7. The dirty worktree is reduced to intentional release changes only before staging.
8. `STRICT_FINAL_RELEASE=1 ./scripts/check-final-release-gates.sh` passes against real artifacts and completed evidence documents.

Use `RUN_EXPENSIVE=1 ./scripts/check-production-readiness.sh` for the local source-level release rehearsal. The default script mode is intentionally lightweight and checks release structure, backup rehearsal, and public-git safety.

## Remaining Work To Reach 100

| Priority | Gap | Impact | Required Action |
| --- | --- | --- | --- |
| P0 | Physical iPhone execution and full manual device checklist remain incomplete | Simulator/emulator automation cannot prove real iPhone install, outdoor contrast, haptics, maximum text size, or assistive-technology behavior | Connect iPhone by USB, run physical E2E, then complete the premium manual checklist on both platforms |
| P0 | Signed mobile artifacts are prepared but unproven | Cannot claim formal mobile distribution until signed APK/IPA artifacts exist | Run `CHECK_SIGNING_SECRETS=1 ./scripts/check-release-artifacts-preflight.sh`, then run Android/iOS release workflows or local signed builds |
| P0 | Real artifact hash and signature evidence is not recorded yet | Release reviewers cannot independently verify which binary was shipped | Download CI artifacts or collect local signed outputs, then run `RELEASE_ARTIFACT_DIR=artifacts RELEASE_VERSION=<version> REQUIRE_IOS_ARTIFACT=1 VERIFY_ARTIFACT_SIGNATURES=1 ./scripts/check-release-artifact-files.sh` and record SHA-256/signature values in `docs/quality/release-artifact-evidence-2026-05-27.md` |
| P0 | Current-candidate Docker publication and deployment smoke evidence is not recorded | The historical v1.0.8 image does not prove the current worktree | Run a new approved tag release, verify its digest/multi-arch manifest, deploy its digest-pinned Compose, and record results in `docs/quality/docker-release-evidence-2026-05-27.md` |
| P1 | Release notes still contain candidate placeholders | Users need accurate platform, limitation, upgrade, and rollback information before install | Finalize `docs/quality/release-notes-candidate-2026-05-27.md` and run `STRICT_RELEASE_NOTES=1 ./scripts/check-release-notes-candidate.sh` |
| P1 | Final release runbook still contains candidate placeholders | Operators need exact version and evidence state before pushing a real release tag | Finalize `docs/quality/final-release-runbook-2026-05-27.md` and run `STRICT_FINAL_RELEASE_RUNBOOK=1 ./scripts/check-final-release-runbook.sh` |
| P2 | Production-environment backup operator drill is optional follow-up | Local isolated API drill proves the release-critical export/restore workflow, but not a deployed operator run | If required for a public release, repeat the drill against a non-local release candidate deployment |
| P1 | VoiceOver/TalkBack pass is manual-only | Accessibility confidence is widget-level, not assistive-tech level | Run real screen-reader pass on release candidate |
| P1 | Final release evidence still contains pending rows | Strict gate will intentionally fail until real artifacts, physical device, and accessibility evidence are recorded | Use `STRICT_FINAL_RELEASE=1 ./scripts/check-final-release-gates.sh` after artifact, physical device, and accessibility evidence is recorded |

## Release Notes Template

```markdown
## Personal Ledger vX.Y.Z

### Supported deployment
- Backend + Web: Docker image `ghcr.io/<owner>/<repo>:X.Y.Z`
- Android: signed APK/AAB artifact
- iOS: signed IPA from `.github/workflows/ios.yml`, TestFlight, or manually signed archive, if available

### Highlights
- Family members and member-linked transactions
- Family summary and mobile Family Hub
- OpenAI-compatible AI reports with aggregated snapshots
- Premium mobile Home, Quick Transaction, AI Reports, and Family Hub screens

### Security and privacy
- AI analysis is optional and disabled until a provider is configured
- AI snapshots exclude raw transaction remarks by default
- AI provider keys are not returned by API responses or normal backups

### Known limitations
- iOS/Android device validation: <PASS/BLOCKED with device and date>
- Screen-reader manual pass: <PASS/PENDING>
- Device-native marketing screenshots: <PASS/PENDING>

### Upgrade notes
- Configure and retain a stable `LEDGER_CREDENTIAL_ENCRYPTION_KEY` before upgrade
- Let startup migrate legacy AI and notification credentials; do not re-save providers only for migration
- Take a backup before upgrading

### Rollback
- Keep the previous Docker image tag
- Keep the pre-upgrade backup export
- Restore only after confirming the target version supports the backup format
```
