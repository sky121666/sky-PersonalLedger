# Final Release Runbook - 2026-05-27

## Conclusion

This runbook is the ordered path from a reviewed release candidate to a fully proven Personal Ledger release. It connects signing setup, CI release, artifact verification, physical-device QA, backup drill, accessibility evidence, release notes, and the strict final gate.

Current status: source-level rehearsal passed on 2026-05-27. External release evidence is intentionally deferred for the current local acceptance scope; real signing, tag release, artifact verification, physical-device QA, and manual VoiceOver/TalkBack remain pending for a later public release.

## Preconditions

| Gate | Command / Evidence | Status |
| --- | --- | --- |
| Source-level rehearsal | `RUN_EXPENSIVE=1 ./scripts/check-production-readiness.sh` | PASS, 2026-05-27 local run |
| Release scope inventory | `STRICT_RELEASE_SCOPE=1 ./scripts/check-release-change-inventory.sh` | PASS |
| Android/iOS workflow structure | `./scripts/check-release-artifacts-preflight.sh` | PASS |
| Public git safety | `./scripts/check-public-git-safety.sh` | PASS |
| Backup service rehearsal | `./scripts/check-backup-restore-rehearsal.sh` | PASS |

## Local Acceptance Mode

Use this mode while external release evidence is intentionally deferred:

```bash
LOCAL_FINAL_RELEASE=1 ./scripts/check-final-release-gates.sh
```

This verifies source readiness, strict change inventory, backup operator drill evidence, local Docker image smoke, local Docker Compose smoke, and whitespace checks. It intentionally skips signed APK/AAB/IPA files, GHCR release image evidence, USB iPhone validation, Android device validation, and manual VoiceOver/TalkBack evidence.

## 1. Configure Signing

Mobile signing is an optional tutorial path and this repository currently has no real signing
material configured. The Docker/Web tag release does not require it. If the formal signed mobile
workflow will be used, first create a protected `mobile-signing` environment and configure these
environment secrets:

```text
ANDROID_KEYSTORE_BASE64
ANDROID_KEYSTORE_PASSWORD
ANDROID_KEY_ALIAS
ANDROID_KEY_PASSWORD
IOS_CERTIFICATE_BASE64
IOS_CERTIFICATE_PASSWORD
IOS_PROVISIONING_PROFILE_BASE64
IOS_EXPORT_OPTIONS_PLIST_BASE64
IOS_KEYCHAIN_PASSWORD
```

Configure the protected repository variables `ANDROID_EXPECTED_SIGNER_SHA256` (64 hexadecimal
characters) and `IOS_EXPECTED_TEAM_IDENTIFIER` (10-character Apple TeamIdentifier). The signed
workflow deliberately fails closed if either expected identity is missing; it compares APK/AAB to
the same expected signer and verifies the iOS TeamIdentifier plus signed application identifier.

Validate the exported variables in a local shell or equivalent CI context without printing their values:

```bash
ANDROID_EXPECTED_SIGNER_SHA256=<64-hex-fingerprint> \
IOS_EXPECTED_TEAM_IDENTIFIER=<10-character-team-id> \
CHECK_SIGNING_SECRETS=1 ./scripts/check-release-artifacts-preflight.sh
```

## 2. Run Release Workflow

Before creating a tag, confirm the GitHub main ruleset, immutable v* tag ruleset, and protected
`release` environment described in
[发布治理合同](../development/release-governance.md). These are remote settings and are not proven
by a local preflight.

Create and push a one-time annotated version tag only after source-level rehearsal passes:

```bash
git tag -a vX.Y.Z -m "Release vX.Y.Z"
git push origin vX.Y.Z
```

The tag-triggered `Release Docker/Web` workflow should:

- verify that the tag commit is contained in origin/main and that neither the Release nor GHCR
  version tag already exists;
- build one OCI layout, export and verify separate amd64/arm64 scan archives, scan both archives, then
  hand off the scanned OCI archive with SHA-256 to a separate protected publisher, which rechecks
  both the archive checksum and OCI digest before pushing the unchanged original layout;
- publish only the immutable `ghcr.io/<owner>/<repo>:X.Y.Z` tag; the workflow does not create or
  update `latest`;
- create the Docker/Web GitHub Release with an immutable digest-specific Compose attachment and
  checksum.

Do not move or recreate a failed/released tag. Diagnose the run and choose a new version when the
historical version has already been published.

If formal mobile assets are required, wait for Docker/Web success, open Actions, select
`Signed Mobile Release (manual)`, choose the exact `vX.Y.Z` tag as the run ref, and enter the same
version. The manual workflow rechecks tag/main ancestry and the existing non-draft Release before it
downloads and checks the exact version Compose/checksum, confirms its digest matches the GHCR
version tag, then builds, verifies, and appends Android/iOS assets. It does not rebuild Docker.

## 3. Download And Verify Artifacts

Download and verify the release-specific Docker Compose pair before deployment:

```bash
gh release download vX.Y.Z --pattern 'docker-compose-vX.Y.Z.yml*'
sha256sum -c docker-compose-vX.Y.Z.yml.sha256
```

Download the GitHub Actions artifacts or release attachments into `artifacts/`, preserving the artifact directory names:

```text
artifacts/android-release/
artifacts/ios-ipa/
```

Verify files, sidecar checksums, and local artifact signatures:

```bash
RELEASE_ARTIFACT_DIR=artifacts RELEASE_VERSION=X.Y.Z REQUIRE_IOS_ARTIFACT=1 VERIFY_ARTIFACT_SIGNATURES=1 ./scripts/check-release-artifact-files.sh
```

Copy the verifier output into:

```text
docs/quality/release-artifact-evidence-2026-05-27.md
```

## 4. Mobile Device QA

Connect the iPhone by USB, unlock it, trust this Mac, confirm Developer Mode is enabled, and start an Android emulator:

```bash
REQUIRE_PHYSICAL_IOS=1 REQUIRE_ANDROID_EMULATOR=1 ./scripts/check-mobile-device-qa-preflight.sh
```

Run real-backend E2E on the USB-connected iPhone when available:

```bash
REQUIRE_PHYSICAL_IOS=1 \
RUN_PHYSICAL_IOS_E2E=1 \
IOS_PHYSICAL_DEVICE_ID=<device-id> \
./scripts/check-mobile-device-qa-preflight.sh
```

Run real-backend E2E on Android when available:

```bash
RUN_ANDROID_E2E=1 ./scripts/check-mobile-device-qa-preflight.sh
```

Record device identity, build identity, screenshots or notes, and result rows in:

```text
docs/quality/mobile-device-qa-checklist-2026-05-27.md
```

## 5. Backup Operator Drill

For the local release-candidate rehearsal, run the isolated source/target API drill:

```bash
./scripts/check-backup-operator-drill-local.sh
```

For a later non-local release deployment, use an isolated target deployment or test account and do not paste tokens into evidence docs. Record the drill result in:

```text
docs/quality/backup-operator-drill-2026-05-27.md
```

## 6. Accessibility Pass

Run the automated baseline:

```bash
cd mobile
flutter test test/premium_accessibility_test.dart
```

Then run manual iOS VoiceOver and Android TalkBack passes for Home, Quick Transaction, AI Reports, and Family Hub. Record results in:

```text
docs/quality/accessibility-release-evidence-2026-05-27.md
```

## 7. Finalize Release Notes

Replace candidate values and pending rows in:

```text
docs/quality/release-notes-candidate-2026-05-27.md
```

Then run:

```bash
STRICT_RELEASE_NOTES=1 ./scripts/check-release-notes-candidate.sh
```

## 8. Final Gate

Run the strict final gate only after all evidence documents are filled:

```bash
STRICT_FINAL_RELEASE=1 ./scripts/check-final-release-gates.sh
```

This strict gate also requires a clean `git status --short` so final release evidence is tied to committed source.
Set `DOCKER_RELEASE_IMAGE=ghcr.io/<owner>/<repo>:X.Y.Z` (and record its resolved digest) when running
the strict gate so the published image manifest and release-image compose smoke are verified live.

The release can be called fully complete only when the strict final gate passes.

## Failure Handling

| Failure | Response |
| --- | --- |
| Missing signing secret or expected identity | Do not retry blindly; configure the protected `mobile-signing` environment secret or administrator-controlled repository variable |
| Tag or Release already exists | Do not move/overwrite it; stop and choose a new version after review |
| Docker architecture scan fails | The Git tag remains as immutable failure evidence, but no GHCR version image tag is published; remediate and release under a new reviewed version/tag |
| Android artifact missing | Check Android workflow logs and release attachment paths |
| iOS IPA missing | Check certificate import, provisioning profile, export options, and bundle ID |
| Artifact checksum mismatch | Discard downloaded artifacts and re-download from the trusted CI/release source |
| USB iPhone not detected | Unlock device, trust Mac, enable Developer Mode, use cable, then rerun preflight |
| Android emulator not detected | Start Android emulator, then rerun preflight |
| Backup drill fails | Keep the failed backup file and target logs for diagnosis, but do not publish release as complete |
| Accessibility fail | Fix or document scoped non-blocking exception, then retest |

Do not paste secrets, token values, keychain passwords, certificate contents, provisioning profile contents, or private URLs into release notes or evidence documents.
