# Production Readiness Gate - 2026-05-27

## Conclusion

Personal Ledger is now on the correct product track for a private/family self-hosted release: family accounting is modeled as an owner-scoped household dimension, AI analysis uses an OpenAI-compatible adapter with aggregated snapshots, and mobile premium screens have simulator/emulator evidence.

This document defines the remaining gates for a 100/100 release. The current state is strong enough for local advanced testing and has passed a source-level local release rehearsal. External release evidence is intentionally deferred for the current local acceptance scope; it is not yet a fully proven public release because physical iPhone validation, signed iOS/Android release artifacts, and store/distribution evidence are still required later.

## Target

| Requirement | Target State | Current Judgment |
| --- | --- | --- |
| Private/family product model | Single owner account with family members as ledger dimensions, not SaaS multi-tenancy | PASS |
| Family functions | Member CRUD, transaction member attribution, family summary, Family Hub UI | PASS for phase 1; family budget/roles remain phase 2 |
| AI reports | OpenAI-compatible provider, weekly/monthly generation, aggregated snapshot, no raw remarks by default | PASS for phase 1 |
| AI secret safety | Provider API keys are not returned by API, not backed up, and are protected at rest for new saves | PASS after AES-GCM protection |
| iOS/Android native quality | Flutter native screens, light/dark premium UI, emulator/simulator smoke, accessibility widget checks | PASS with physical iPhone and manual screen-reader gaps |
| Physical device proof | Real iPhone and Android device/simulator platform checks | PARTIAL; iPhone USB validation remains missing |
| Formal distribution | Docker image, signed Android APK/AAB artifact path, signed iOS artifact path, release notes, repeatable tag workflow | PARTIAL; Android APK/AAB workflow exists, iOS workflow is prepared, signing secrets have not yet produced real artifacts |
| Recovery | Backup scope documented and restore rehearsal covers family member, member-linked transaction, and AI report history | PASS for automated rehearsal and local isolated operator drill |

## Release Gate Matrix

| Gate | Required Evidence | Status | Command / Artifact |
| --- | --- | --- | --- |
| Backend regression | All backend unit/integration-safe tests pass | REQUIRED | `cd backend && go test ./...` |
| Web build | Web production build passes with pnpm only | REQUIRED | `cd web && pnpm install && pnpm build` |
| Mobile static gate | Flutter analyzer and widget tests pass | PASS in latest QA | `cd mobile && flutter analyze && flutter test` |
| Real backend E2E | Mobile app exercises real auth/account/transaction flow | PASS on flutter-tester, iOS Simulator, Android Emulator | `./scripts/verify-mobile-e2e.sh` plus platform flags |
| Premium screen smoke | Home, Quick Transaction, AI Reports, Family Hub render in light/dark | PASS | `cd mobile && flutter test integration_test/premium_screens_smoke_test.dart` |
| Android release | Signed release APK/AAB built from CI or local secrets | PREPARED, NOT PROVEN | `.github/workflows/android.yml`, `docs/android-release-signing.md`, then Android release workflow evidence |
| iOS release | Archive, TestFlight build, or signed IPA from configured signing identity | PREPARED, NOT PROVEN | `.github/workflows/ios.yml`, `docs/ios-release-signing.md`, then `flutter build ipa --release` evidence |
| Physical iPhone | USB-connected device runs smoke or install/manual checklist | MISSING | `flutter test -d <physical-id> integration_test/app_smoke_test.dart` |
| Backup rehearsal | Export, restore into isolated database, verify family member, member-linked transaction, and AI report history | PASS automated | `./scripts/check-backup-restore-rehearsal.sh` |
| Backup operator drill | Real app/API export and restore workflow has release-candidate evidence | PASS local isolated API drill | `./scripts/check-backup-operator-drill-local.sh`; `STRICT_BACKUP_OPERATOR_DRILL=1 ./scripts/check-backup-operator-drill.sh` |
| Runtime health endpoint | Public health route checks database, schema version, and storage directories without exposing secrets | PASS contract; release runtime smoke still required | `./scripts/check-runtime-health-contract.sh`; `curl -fsS http://127.0.0.1:8080/api/v1/health` |
| AI privacy contract | Provider keys stay out of responses/backups, reports exclude raw remarks, manual and scheduled snapshots can mask member names | REQUIRED | `./scripts/check-ai-privacy-contract.sh` |
| AI provider security | Stored keys encrypted, responses omit raw key, backups omit provider secrets | PASS for new provider saves | `cd backend && go test ./internal/service -run 'AIProvider|Backup' -count=1` |
| Public git safety | No keys, token, private key, env files, or local database artifacts in commit | REQUIRED | `./scripts/check-public-git-safety.sh` and `git status --short` |
| Production readiness structure | Release docs, Android/iOS workflows, pnpm-only web lockfiles, backup rehearsal, and public safety scan are present/clean | PREPARED | `./scripts/check-production-readiness.sh` |
| Local release rehearsal | Backend, web, mobile, premium smoke, backup rehearsal, safety scan, and real-backend mobile E2E pass from the current working tree | PASS local | `RUN_EXPENSIVE=1 ./scripts/check-production-readiness.sh` |
| Release artifact preflight | Android/iOS signing workflows, release artifact naming, bundle id/team id, and optional signing-secret presence are checkable | PREPARED | `./scripts/check-release-artifacts-preflight.sh`; use `CHECK_SIGNING_SECRETS=1` before release |
| Docker release preflight | GHCR workflow, tag release integration, multi-arch image target, Dockerfile runtime, healthcheck, and compose secret guard are checkable | PREPARED | `./scripts/check-docker-release-preflight.sh` |
| Local Docker smoke | Current worktree can be built into a Docker image and booted with a temporary `/data` mount | OPTIONAL EXPENSIVE | `RUN_EXPENSIVE=1 RUN_DOCKER_LOCAL_SMOKE=1 ./scripts/check-production-readiness.sh` or `./scripts/check-docker-local-smoke.sh` |
| Local Docker Compose smoke | Current worktree image can boot through Compose with a persistent `/data` mount and JWT guard | OPTIONAL EXPENSIVE | `RUN_EXPENSIVE=1 RUN_DOCKER_COMPOSE_LOCAL_SMOKE=1 ./scripts/check-production-readiness.sh` or `./scripts/check-docker-compose-local-smoke.sh` |
| Docker release evidence | Published image manifest and optional compose smoke can be checked after tag release | PREPARED, AWAITING REAL IMAGE | `DOCKER_RELEASE_IMAGE=ghcr.io/<owner>/<repo>:<version> ./scripts/check-docker-release-evidence.sh` |
| Release artifact file evidence | Produced APK/AAB/IPA files can be checked for naming, size, zip validity, sidecar checksums, and SHA-256 evidence | PREPARED, AWAITING REAL ARTIFACTS | `RELEASE_ARTIFACT_DIR=artifacts RELEASE_VERSION=<version> ./scripts/check-release-artifact-files.sh` |
| Release notes candidate | Supported platforms, limitations, upgrade notes, rollback, and verification summary are checkable | PREPARED, AWAITING FINAL VALUES | `./scripts/check-release-notes-candidate.sh`; use `STRICT_RELEASE_NOTES=1` before release |
| Release change inventory | Worktree changes have a path-by-path review template and forbidden local/generated files are checked | PREPARED, AWAITING PATH REVIEW | `./scripts/check-release-change-inventory.sh`; use `STRICT_RELEASE_SCOPE=1` before staging/release |
| Final release runbook | Signing, tag release, artifact verification, physical QA, backup drill, accessibility, release notes, and final gate are ordered | PREPARED, AWAITING FINAL VALUES | `./scripts/check-final-release-runbook.sh`; use `STRICT_FINAL_RELEASE_RUNBOOK=1` before release |
| Mobile device QA preflight | Current device list is inspectable, wireless iPhone is distinguished from USB iPhone, and physical E2E has a fixed command | PREPARED | `./scripts/check-mobile-device-qa-preflight.sh`; use `REQUIRE_PHYSICAL_IOS=1` for release |
| Accessibility release evidence | Automated premium accessibility baseline passes; VoiceOver/TalkBack manual evidence template and pass criteria are defined | PARTIAL, AWAITING REAL ASSISTIVE-TECH PASS | `docs/quality/accessibility-release-evidence-2026-05-27.md` |
| Final release gate | Structural readiness plus optional strict final proof for artifacts, physical iPhone, and accessibility evidence | PREPARED | `./scripts/check-final-release-gates.sh`; use `STRICT_FINAL_RELEASE=1` only for a real release candidate |
| Local final acceptance gate | Source readiness plus strict local-only proof while external release evidence is deferred | PREPARED | `LOCAL_FINAL_RELEASE=1 ./scripts/check-final-release-gates.sh` |

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
| P0 | Physical iPhone is wireless-only in current evidence | Cannot prove real iOS install, safe area, keyboard, haptics, and performance | Connect by USB and run app smoke plus premium manual checklist |
| P0 | Signed mobile artifacts are prepared but unproven | Cannot claim formal mobile distribution until signed APK/IPA artifacts exist | Run `CHECK_SIGNING_SECRETS=1 ./scripts/check-release-artifacts-preflight.sh`, then run Android/iOS release workflows or local signed builds |
| P0 | Real artifact hash evidence is not recorded yet | Release reviewers cannot independently verify which binary was shipped | Download CI artifacts or collect local signed outputs, then run `RELEASE_ARTIFACT_DIR=artifacts RELEASE_VERSION=<version> ./scripts/check-release-artifact-files.sh` and record SHA-256 values in `docs/quality/release-artifact-evidence-2026-05-27.md` |
| P0 | Docker image publication and deployment smoke evidence is not recorded yet | Cannot prove the primary one-place deployment path works from the published image | Run tag release, verify GHCR digest/multi-arch manifest, deploy with docker compose, and record results in `docs/quality/docker-release-evidence-2026-05-27.md` |
| P1 | Release notes still contain candidate placeholders | Users need accurate platform, limitation, upgrade, and rollback information before install | Finalize `docs/quality/release-notes-candidate-2026-05-27.md` and run `STRICT_RELEASE_NOTES=1 ./scripts/check-release-notes-candidate.sh` |
| P1 | Worktree change inventory is not finalized | Large dirty worktree increases review, staging, rollback, and release risk | Fill `docs/quality/release-change-inventory-2026-05-27.md` with every changed path and run `STRICT_RELEASE_SCOPE=1 ./scripts/check-release-change-inventory.sh` |
| P1 | Final release runbook still contains candidate placeholders | Operators need exact version and evidence state before pushing a real release tag | Finalize `docs/quality/final-release-runbook-2026-05-27.md` and run `STRICT_FINAL_RELEASE_RUNBOOK=1 ./scripts/check-final-release-runbook.sh` |
| P2 | Production-environment backup operator drill is optional follow-up | Local isolated API drill proves the release-critical export/restore workflow, but not a deployed operator run | If required for a public release, repeat the drill against a non-local release candidate deployment |
| P1 | AI provider rotation path is manual | Existing plain legacy keys remain possible until re-saved | Document "save provider again after upgrade" and add future migration if needed |
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
- Physical iPhone validation: <PASS/BLOCKED with device and date>
- Screen-reader manual pass: <PASS/PENDING>
- Device-native marketing screenshots: <PASS/PENDING>

### Upgrade notes
- Re-save existing AI providers after upgrade to protect legacy stored keys
- Take a backup before upgrading

### Rollback
- Keep the previous Docker image tag
- Keep the pre-upgrade backup export
- Restore only after confirming the target version supports the backup format
```
