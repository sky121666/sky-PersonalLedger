# Android Release Signing

Android production APKs and App Bundles must be signed with a release keystore. The Gradle build intentionally fails release builds when signing is missing, so a release artifact cannot silently fall back to the debug key.

Release builds also default to `android:usesCleartextTraffic=false`. Debug builds keep cleartext enabled for emulator and local HTTP testing, but production Android artifacts should connect to the ledger backend through HTTPS. If a private LAN deployment explicitly requires HTTP, the release build must opt in with `-PledgerAllowReleaseCleartext=true`; do not use that override for public distribution.

The build flag only permits the Android transport. The client URL validator still limits HTTP to
private/loopback hosts and requires an explicit risk confirmation before connecting; it does not make
public HTTP acceptable.

## Local Release Build

1. Generate or place the upload keystore under `mobile/android/app/upload-keystore.jks`.
2. Copy `mobile/android/key.properties.example` to `mobile/android/key.properties`.
3. Fill the real values:

```properties
storeFile=app/upload-keystore.jks
storePassword=<keystore-password>
keyAlias=upload
keyPassword=<key-password>
```

4. Build:

```bash
cd mobile
flutter build apk --release
flutter build appbundle --release
```

For a private, non-store LAN build that must connect to an HTTP-only backend, use the explicit override:

```bash
flutter build apk --release -PledgerAllowReleaseCleartext=true
flutter build appbundle --release -PledgerAllowReleaseCleartext=true
```

`mobile/android/key.properties` and keystore files are ignored by git.

## GitHub Actions

`.github/workflows/android.yml` may build a signed artifact directly for controlled testing and is
also called by `Signed Mobile Release (manual)`. Pushing a vX.Y.Z tag publishes Docker/Web first; it
does not automatically build or attach Android artifacts. Run the signed mobile workflow from that
exact existing tag only after the Docker/Web Release succeeds.

This is an optional signing tutorial. The repository currently does not configure real signing
material. If formal signed publishing is enabled, create and protect the `mobile-signing`
environment, then configure these environment secrets:

- `ANDROID_KEYSTORE_BASE64`: base64-encoded release keystore file
- `ANDROID_KEYSTORE_PASSWORD`: keystore password
- `ANDROID_KEY_ALIAS`: key alias
- `ANDROID_KEY_PASSWORD`: key password

Also configure the administrator-protected repository variable
`ANDROID_EXPECTED_SIGNER_SHA256` to the release certificate SHA-256 fingerprint as exactly 64
hexadecimal characters. The workflow fails closed when this identity is absent or malformed. It
compares both the APK and AAB signer to that fingerprint and also requires both artifacts to use the
same signer. Do not commit a real fingerprint or signing material as a repository default.

The Android workflow decodes the keystore into `mobile/android/app/upload-keystore.jks`, writes `mobile/android/key.properties`, and then builds both:

- `personal-ledger-<version>-android.apk`
- `personal-ledger-<version>-android.aab`
- `personal-ledger-<version>-android.apk.sha256`
- `personal-ledger-<version>-android.aab.sha256`

The APK is useful for direct install testing. The AAB is the preferred artifact for formal store distribution.

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

For a local Android signing setup, this checks that the ignored signing files exist:

```bash
CHECK_LOCAL_ANDROID_SIGNING=1 ./scripts/check-release-artifacts-preflight.sh
```

After CI or a local release build produces artifacts, verify the actual files, signatures, and SHA-256 values:

```bash
ANDROID_EXPECTED_SIGNER_SHA256=<64-hex-fingerprint> \
RELEASE_ARTIFACT_DIR=artifacts RELEASE_VERSION=<version> \
VERIFY_ARTIFACT_SIGNATURES=1 ./scripts/check-release-artifact-files.sh
```

The verifier requires `.sha256` sidecar files, checks that they match the downloaded APK/AAB files, and verifies Android release signatures when `VERIFY_ARTIFACT_SIGNATURES=1` is set.
