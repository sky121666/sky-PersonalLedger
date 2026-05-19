# Android Release Signing

Android production APKs must be signed with a release keystore. The Gradle build intentionally fails release builds when signing is missing, so a release artifact cannot silently fall back to the debug key.

## Local Release Build

1. Generate or place the upload keystore under `mobile/android/app/upload-keystore.jks`.
2. Copy `mobile/android/key.properties.example` to `mobile/android/key.properties`.
3. Fill the real values:

```properties
storeFile=app/upload-keystore.jks
storePassword=your-store-password
keyAlias=upload
keyPassword=your-key-password
```

4. Build:

```bash
cd mobile
flutter build apk --release
```

`mobile/android/key.properties` and keystore files are ignored by git.

## GitHub Actions

Configure these repository secrets:

- `ANDROID_KEYSTORE_BASE64`: base64-encoded release keystore file
- `ANDROID_KEYSTORE_PASSWORD`: keystore password
- `ANDROID_KEY_ALIAS`: key alias
- `ANDROID_KEY_PASSWORD`: key password

The Android workflow decodes the keystore into `mobile/android/app/upload-keystore.jks`, writes `mobile/android/key.properties`, and then builds the release APK.
