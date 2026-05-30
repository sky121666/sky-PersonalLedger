# iOS Release Signing

iOS production builds require Apple signing material. The iOS workflow can be run manually or reused by the tag release workflow once the certificate, provisioning profile, and export options are configured as repository secrets.

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

`.github/workflows/ios.yml` is both a manual workflow and a reusable workflow for the tag release pipeline. Configure these repository secrets before running it directly or pushing a release tag:

| Secret | Purpose |
| --- | --- |
| `IOS_CERTIFICATE_BASE64` | Base64-encoded `.p12` signing certificate |
| `IOS_CERTIFICATE_PASSWORD` | Password for the `.p12` file |
| `IOS_PROVISIONING_PROFILE_BASE64` | Base64-encoded `.mobileprovision` for `com.skyapp.personalLedger` |
| `IOS_EXPORT_OPTIONS_PLIST_BASE64` | Base64-encoded `ExportOptions.plist` |
| `IOS_KEYCHAIN_PASSWORD` | Temporary CI keychain password |

The workflow installs the signing material into a temporary keychain, runs `flutter analyze`, runs `flutter test`, builds a release IPA, and uploads `personal-ledger-<version>-ios.ipa` as an artifact. The tag release workflow attaches the IPA when the reusable iOS job succeeds.

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
CHECK_SIGNING_SECRETS=1 ./scripts/check-release-artifacts-preflight.sh
```

For a local iOS signing setup, this checks that the ignored export options plist exists and is valid:

```bash
CHECK_LOCAL_IOS_SIGNING=1 ./scripts/check-release-artifacts-preflight.sh
```

After CI or a local signed export produces an IPA, verify the actual file and record its SHA-256 value:

```bash
RELEASE_ARTIFACT_DIR=artifacts RELEASE_VERSION=<version> REQUIRE_ANDROID_ARTIFACTS=0 REQUIRE_IOS_ARTIFACT=1 ./scripts/check-release-artifact-files.sh
```

The verifier requires the `.sha256` sidecar file and checks that it matches the downloaded IPA file.
