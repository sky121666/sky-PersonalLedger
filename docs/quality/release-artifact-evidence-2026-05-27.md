# Release Artifact Evidence - 2026-05-27

## Conclusion

This document is the release-candidate evidence log for signed mobile artifacts. A release is not considered fully proven until the Android APK/AAB and, when iOS distribution is in scope, the iOS IPA or TestFlight/archive evidence is recorded here with hashes and source workflow links.

Current status: structural release evidence is prepared, source-level rehearsal has passed, local isolated backup operator drill has passed, automated accessibility baseline has passed, and external release evidence is intentionally deferred for the current local acceptance scope. Real signed artifacts, physical-device evidence, manual VoiceOver/TalkBack pass, and final release values remain pending for a later public release.

## Artifact Verification Command

Run from the repository root after downloading CI artifacts or collecting local signed build outputs:

```bash
RELEASE_ARTIFACT_DIR=artifacts RELEASE_VERSION=<version> ./scripts/check-release-artifact-files.sh
```

For iOS-only verification:

```bash
RELEASE_ARTIFACT_DIR=artifacts RELEASE_VERSION=<version> REQUIRE_ANDROID_ARTIFACTS=0 REQUIRE_IOS_ARTIFACT=1 ./scripts/check-release-artifact-files.sh
```

For a full Android + iOS release candidate:

```bash
RELEASE_ARTIFACT_DIR=artifacts RELEASE_VERSION=<version> REQUIRE_IOS_ARTIFACT=1 ./scripts/check-release-artifact-files.sh
```

## Evidence Table

| Artifact | Required File | Status | SHA-256 | Source |
| --- | --- | --- | --- | --- |
| Android APK | `personal-ledger-<version>-android.apk` | PENDING |  | `.github/workflows/android.yml` or local signed build |
| Android APK checksum | `personal-ledger-<version>-android.apk.sha256` | PENDING |  | `.github/workflows/android.yml` or local checksum |
| Android AAB | `personal-ledger-<version>-android.aab` | PENDING |  | `.github/workflows/android.yml` or local signed build |
| Android AAB checksum | `personal-ledger-<version>-android.aab.sha256` | PENDING |  | `.github/workflows/android.yml` or local checksum |
| iOS IPA | `personal-ledger-<version>-ios.ipa` | PENDING |  | `.github/workflows/ios.yml`, tag release, local archive, or TestFlight export |
| iOS IPA checksum | `personal-ledger-<version>-ios.ipa.sha256` | PENDING |  | `.github/workflows/ios.yml`, tag release, or local checksum |

## Release Candidate Checklist

| Gate | Required Evidence | Status |
| --- | --- | --- |
| Docker release structure | `./scripts/check-docker-release-preflight.sh` passes | PASS |
| Docker image publication | `docs/quality/docker-release-evidence-2026-05-27.md` records GHCR version tag, digest, and multi-arch manifest | PENDING |
| Docker deployment smoke | `docs/quality/docker-release-evidence-2026-05-27.md` records docker compose pull/start/health/persistence evidence | PENDING |
| Android signing secrets | `CHECK_SIGNING_SECRETS=1 ./scripts/check-release-artifacts-preflight.sh` passes in CI or equivalent local environment | PENDING |
| Android artifacts | APK and AAB pass `check-release-artifact-files.sh` | PENDING |
| Android checksums | APK/AAB `.sha256` files are attached to the CI artifact or GitHub Release and match downloaded files | PENDING |
| iOS signing material | iOS workflow or local export validates certificate, provisioning profile, and export options | PENDING |
| iOS artifact | IPA, TestFlight build, or Xcode archive is recorded with version/build number | PENDING |
| iOS checksum | IPA `.sha256` file is attached to the CI artifact and matches the downloaded file | PENDING |
| Physical iPhone | USB-connected iPhone E2E or signed-install manual checklist is recorded | PENDING |
| Backup operator drill structure | `./scripts/check-backup-operator-drill.sh` passes | PASS |
| Backup operator drill execution | `docs/quality/backup-operator-drill-2026-05-27.md` records real export/restore evidence from an isolated deployment | PASS |
| Release notes structure | `./scripts/check-release-notes-candidate.sh` passes | PASS |
| Release notes final values | `STRICT_RELEASE_NOTES=1 ./scripts/check-release-notes-candidate.sh` passes | PENDING |
| Release change inventory | `docs/quality/release-change-inventory-2026-05-27.md` lists every changed path and passes `STRICT_RELEASE_SCOPE=1 ./scripts/check-release-change-inventory.sh` | PASS |
| Final release runbook structure | `./scripts/check-final-release-runbook.sh` passes | PASS |
| Final release runbook values | `STRICT_FINAL_RELEASE_RUNBOOK=1 ./scripts/check-final-release-runbook.sh` passes | PENDING |
| Local final acceptance | `LOCAL_FINAL_RELEASE=1 ./scripts/check-final-release-gates.sh` passes while external evidence is deferred | PASS REQUIRED FOR CURRENT SCOPE |

## Recording Format

Copy the verifier output into the release note or PR description:

```text
Release artifact evidence:
<sha256>    <size> bytes    <path>
Release artifact file checks passed.
```

Do not paste signing secrets, key aliases, certificate passwords, provisioning profile contents, or full CI environment values into this document.
