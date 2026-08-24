# Final Release Runbook - v1.0.9

## Conclusion

This is the exact operating path for the v1.0.9 Docker/Web release. Mobile source and simulator or
emulator behavior are verified development targets, but signed APK, AAB, IPA, TestFlight, physical
iPhone, VoiceOver, and TalkBack evidence are outside this release. Docker/Web publication does not
require mobile signing material.

## Preconditions

| Gate | Command or evidence | Status |
| --- | --- | --- |
| Version consistency | `./scripts/check-version-consistency.sh` | PASS for 1.0.9 |
| Source rehearsal | `RUN_EXPENSIVE=1 ./scripts/check-production-readiness.sh` | PASS on 2026-08-24 |
| Local final acceptance | `LOCAL_FINAL_RELEASE=1 ./scripts/check-final-release-gates.sh` | PASS on 2026-08-24 |
| Release scope inventory | `STRICT_RELEASE_SCOPE=1 ./scripts/check-release-change-inventory.sh` | PASS |
| Release notes | `STRICT_RELEASE_NOTES=1 ./scripts/check-release-notes-candidate.sh` | REQUIRED BEFORE TAG |
| Runbook values | `STRICT_FINAL_RELEASE_RUNBOOK=1 ./scripts/check-final-release-runbook.sh` | REQUIRED BEFORE TAG |
| Public repository safety | `./scripts/check-public-git-safety.sh` | REQUIRED BEFORE COMMIT AND TAG |
| Remote target | GitHub `sky121666/sky-PersonalLedger`, protected `main`, unused `v1.0.9` | REQUIRED BEFORE TAG |

## 1. Configure Signing

No signing material is needed for v1.0.9 because its formal scope is Docker/Web. Do not configure,
upload, or request mobile keys merely to publish this version.

For a future separately approved signed-mobile distribution, validate administrator-provided
environment secrets without printing them:

```bash
ANDROID_EXPECTED_SIGNER_SHA256=redacted-local-value \
IOS_EXPECTED_TEAM_IDENTIFIER=redacted-local-value \
CHECK_SIGNING_SECRETS=1 ./scripts/check-release-artifacts-preflight.sh
```

The real values belong only in the protected `mobile-signing` environment or a restricted local
shell. Never put them in source, `.env.example`, logs, issues, release notes, or screenshots.

## 2. Run Release Workflow

Merge the reviewed release commit to `main`, confirm the resulting commit contains root version
`1.0.9`, then create the one-time annotated tag:

```bash
git fetch origin main
git merge-base --is-ancestor HEAD origin/main
git tag -a v1.0.9 -m "Release v1.0.9"
git push origin v1.0.9
```

The tag-triggered `Release Docker/Web` workflow must verify main ancestry and unused version state,
run Web, backend, public-safety, backup, and security gates, build and scan one multi-architecture
OCI layout, publish the unchanged scanned layout, and create a non-draft GitHub Release. It publishes
only `ghcr.io/sky121666/sky-personalledger:1.0.9`; it does not create or move `latest`.

Do not move, recreate, or force-push the tag. If immutable publication has occurred and a defect
requires source changes, prepare a new reviewed version.

## 3. Download And Verify Artifacts

Verify the two in-scope Release assets:

```bash
gh release download v1.0.9 --pattern 'docker-compose-v1.0.9.yml*'
sha256sum -c docker-compose-v1.0.9.yml.sha256
```

Confirm the Compose image is digest-pinned, matches the GHCR `1.0.9` manifest digest, and has both
`linux/amd64` and `linux/arm64` manifests. Then run the published-image smoke:

```bash
DOCKER_RELEASE_IMAGE=ghcr.io/sky121666/sky-personalledger:1.0.9 \
STRICT_DOCKER_RELEASE_EVIDENCE=1 \
RUN_DOCKER_RELEASE_SMOKE=1 \
./scripts/check-docker-release-evidence.sh
```

If a future separately approved mobile release appends signed artifacts, verify them with:

```bash
RELEASE_ARTIFACT_DIR=artifacts RELEASE_VERSION=1.0.9 REQUIRE_IOS_ARTIFACT=1 VERIFY_ARTIFACT_SIGNATURES=1 ./scripts/check-release-artifact-files.sh
```

Record optional signed-artifact results in
`docs/quality/release-artifact-evidence-2026-05-27.md`; this file is not an in-scope v1.0.9 asset.

## 4. Mobile Device QA

Android emulator and iOS Simulator real-backend E2E passed for the current source. They are
development evidence, not signed-install or physical-iPhone claims.

For a future signed-mobile release, require both targets and record results in
`docs/quality/mobile-device-qa-checklist-2026-05-27.md`:

```bash
REQUIRE_PHYSICAL_IOS=1 REQUIRE_ANDROID_EMULATOR=1 ./scripts/check-mobile-device-qa-preflight.sh
RUN_ANDROID_E2E=1 ./scripts/check-mobile-device-qa-preflight.sh
```

## 5. Backup Operator Drill

The isolated local source/target API drill is part of the current source evidence:

```bash
./scripts/check-backup-operator-drill-local.sh
```

Before upgrading a real installation, take a data-directory and restricted `.env` backup. Record a
future deployment-specific drill in `docs/quality/backup-operator-drill-2026-05-27.md` without tokens,
credentials, private URLs, or user data.

## 6. Accessibility Pass

The automated baseline is included in the verified Flutter suite:

```bash
cd mobile
flutter test test/premium_accessibility_test.dart
```

Manual VoiceOver and TalkBack are outside the v1.0.9 Docker/Web scope. If signed mobile distribution
is later approved, record the manual pass in
`docs/quality/accessibility-release-evidence-2026-05-27.md` before making accessibility claims.

## 7. Finalize Release Notes

The v1.0.9 platform scope, limitations, upgrade path, rollback path, and verification boundary are
recorded in `docs/quality/release-notes-candidate-2026-05-27.md`. Validate them before tagging:

```bash
STRICT_RELEASE_NOTES=1 ./scripts/check-release-notes-candidate.sh
```

## 8. Final Gate

Before commit and tag, require clean `git status --short`, strict notes/runbook/inventory checks,
public-git safety, version consistency, and the approved local rehearsal. After tag publication,
require the GHCR manifest, Compose checksum, and release-image compose smoke from section 3.

The repository-wide signed-mobile gate remains available for a future broader release:

```bash
STRICT_FINAL_RELEASE=1 ./scripts/check-final-release-gates.sh
```

It intentionally requires signed mobile files, physical iPhone QA, Android QA, and manual
accessibility evidence, so it is not the completion criterion for this Docker/Web-only release.

## Failure Handling

| Failure | Response |
| --- | --- |
| Tag or Release already exists | Stop; do not move or overwrite it, and prepare a new reviewed version if source must change |
| Main ancestry check fails | Merge the reviewed commit through the protected branch before tagging |
| Docker architecture scan fails | Do not publish or retry by bypassing the scan; diagnose and prepare a new version when required |
| GHCR tag already exists | Stop because the version is not unused; never overwrite the immutable version tag |
| Release environment waits for approval | Approve only after matching tag, commit, workflow, and scanned digest are reviewed |
| Compose checksum mismatch | Discard the files and download the exact v1.0.9 assets again |
| Manifest lacks amd64 or arm64 | Do not deploy; treat the Docker/Web release as failed |
| Published-image smoke fails | Preserve logs and temporary evidence, do not describe the release as complete, and prepare a corrected version |
| Missing signing secret or expected identity | Ignore for v1.0.9; configure protected signing only for a separately approved mobile release |
| Android emulator not detected | Start Android emulator and rerun preflight for a future mobile validation |
| USB iPhone not detected | Unlock, trust, cable-connect, and enable Developer Mode before a future physical-device validation |

Do not paste secrets, tokens, passwords, certificates, provisioning profiles, private URLs, or real
ledger data into commands, logs, evidence documents, screenshots, issues, or Release text.
