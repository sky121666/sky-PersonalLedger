# Android Release Signing

Android production APKs and App Bundles must be signed with a release keystore. The Gradle build intentionally fails release builds when signing is missing, so a release artifact cannot silently fall back to the debug key.

Release builds also default to `android:usesCleartextTraffic=false`. Debug builds keep cleartext enabled for emulator and local HTTP testing, but production Android artifacts should connect to the ledger backend through HTTPS. If a private LAN deployment explicitly requires HTTP, the release build must opt in with `-PledgerAllowReleaseCleartext=true`; do not use that override for public distribution.

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

Configure these repository secrets:

- `ANDROID_KEYSTORE_BASE64`: base64-encoded release keystore file
- `ANDROID_KEYSTORE_PASSWORD`: keystore password
- `ANDROID_KEY_ALIAS`: key alias
- `ANDROID_KEY_PASSWORD`: key password

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
CHECK_SIGNING_SECRETS=1 ./scripts/check-release-artifacts-preflight.sh
```

For a local Android signing setup, this checks that the ignored signing files exist:

```bash
CHECK_LOCAL_ANDROID_SIGNING=1 ./scripts/check-release-artifacts-preflight.sh
```

After CI or a local release build produces artifacts, verify the actual files and record their SHA-256 values:

```bash
RELEASE_ARTIFACT_DIR=artifacts RELEASE_VERSION=<version> ./scripts/check-release-artifact-files.sh
```

The verifier requires `.sha256` sidecar files and checks that they match the downloaded APK/AAB files.
