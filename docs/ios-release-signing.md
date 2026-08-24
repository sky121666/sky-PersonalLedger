# iOS Release Signing

iOS production builds require Apple signing material. The iOS workflow can be run manually for
controlled testing or reused by `Signed Mobile Release (manual)` once the certificate, provisioning
profile, and export options are configured in a protected signing environment. The vX.Y.Z tag workflow itself
publishes Docker/Web only.

## Current App Identity

| Item | Value |
| --- | --- |
| Bundle ID | `com.skyapp.personalLedger` |
| Display name | `Personal Ledger` |
| Team ID in Xcode project | `WV9H55K7S3` |
| Minimum release artifact | signed `.ipa` |

## Local Release Build

Prepare signing in Xcode first, then run from the repository root:

```bash
cd mobile
flutter pub get
flutter build ipa --release --build-name=<version> --build-number=<build-number>
```

If automatic signing is not enough, export with an explicit options plist:

```bash
cd mobile
flutter build ipa --release \
  --build-name=<version> \
  --build-number=<build-number> \
  --export-options-plist=ios/ExportOptions.plist
```

`mobile/ios/ExportOptions.plist`, local certificates, profiles, and keychain material must not be committed.

## GitHub Actions

`.github/workflows/ios.yml` is both a manual workflow and a reusable workflow for the signed mobile
orchestrator. This is an optional signing tutorial; the repository currently does not configure real
signing material. If formal signed publishing is enabled, create and protect the `mobile-signing`
environment, then configure these environment secrets before running it directly or invoking the
signed mobile workflow from an existing release tag:

| Secret | Purpose |
| --- | --- |
| `IOS_CERTIFICATE_BASE64` | Base64-encoded `.p12` signing certificate |
| `IOS_CERTIFICATE_PASSWORD` | Password for the `.p12` file |
| `IOS_PROVISIONING_PROFILE_BASE64` | Base64-encoded `.mobileprovision` for `com.skyapp.personalLedger` |
| `IOS_EXPORT_OPTIONS_PLIST_BASE64` | Base64-encoded `ExportOptions.plist` |
| `IOS_KEYCHAIN_PASSWORD` | Temporary CI keychain password |

Also configure the administrator-protected repository variable `IOS_EXPECTED_TEAM_IDENTIFIER` to
the expected 10-character Apple TeamIdentifier. The workflow fails closed when it is absent or
malformed. It verifies the exported app's TeamIdentifier and requires its signed
`application-identifier` to equal `<TeamIdentifier>.com.skyapp.personalLedger`. The Team ID present
in the Xcode project is build configuration, not trusted evidence of the downloaded artifact's
signing identity. Do not commit signing material or a fallback expected identity.

The workflow installs the signing material into a temporary keychain, runs `flutter analyze`, runs
`flutter test`, builds a release IPA, and uploads `personal-ledger-<version>-ios.ipa` as an artifact.
The manual signed mobile workflow verifies the existing tag/main ancestry and Docker/Web Release,
then attaches the IPA without overwriting an existing asset.

The workflow also uploads `personal-ledger-<version>-ios.ipa.sha256` so the downloaded IPA can be verified after CI export.

## ExportOptions Template

Use this as a starting point for ad-hoc distribution. For TestFlight/App Store distribution, set `method` to `app-store-connect` and use the matching App Store provisioning profile.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>ad-hoc</string>
  <key>teamID</key>
  <string>WV9H55K7S3</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>provisioningProfiles</key>
  <dict>
    <key>com.skyapp.personalLedger</key>
    <string>Personal Ledger Ad Hoc</string>
  </dict>
</dict>
</plist>
```

## Release Gate

Do not claim iOS formal distribution is complete until one of these is true:

- a signed IPA artifact is produced by `.github/workflows/ios.yml`;
- or a local Xcode archive/TestFlight upload is completed and recorded in the release notes.

Physical-device validation is a separate gate. A signed IPA proves distribution packaging, but it does not replace a USB iPhone smoke test.

## Preflight

Run the structural artifact preflight from the repository root:

```bash
./scripts/check-release-artifacts-preflight.sh
```

Before an actual signed release, run it with signing-secret validation in the CI environment or a local shell where the same variables are exported:

```bash
ANDROID_EXPECTED_SIGNER_SHA256=<64-hex-fingerprint> \
IOS_EXPECTED_TEAM_IDENTIFIER=<10-character-team-id> \
CHECK_SIGNING_SECRETS=1 ./scripts/check-release-artifacts-preflight.sh
```

For a local iOS signing setup, this checks that the ignored export options plist exists and is valid:

```bash
CHECK_LOCAL_IOS_SIGNING=1 ./scripts/check-release-artifacts-preflight.sh
```

After CI or a local signed export produces an IPA, verify the actual file, signature, bundle id, and SHA-256 value:

```bash
IOS_EXPECTED_TEAM_IDENTIFIER=<10-character-team-id> \
RELEASE_ARTIFACT_DIR=artifacts RELEASE_VERSION=<version> \
REQUIRE_ANDROID_ARTIFACTS=0 REQUIRE_IOS_ARTIFACT=1 \
VERIFY_ARTIFACT_SIGNATURES=1 ./scripts/check-release-artifact-files.sh
```

The verifier requires the `.sha256` sidecar file, checks that it matches the downloaded IPA file, and verifies the app bundle signature and bundle id when `VERIFY_ARTIFACT_SIGNATURES=1` is set.
