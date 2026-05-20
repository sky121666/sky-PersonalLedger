# Mobile Platform Validation - 2026-05-20

## Scope

This pass focused on native Android and Apple platform readiness after the attachment and backup hardening work.

## Fixes

- Android launcher label now uses the user-facing name `Personal Ledger`.
- iOS declares local network usage and allows local-network HTTP through ATS for self-hosted ledger servers.
- macOS declares local network usage and allows local-network HTTP through ATS for self-hosted ledger servers.
- macOS sandbox entitlements now allow reading files selected by the user, which is required for backup restore and attachment upload.

## Verification

Completed:

- `plutil -lint mobile/ios/Runner/Info.plist mobile/macos/Runner/Info.plist mobile/macos/Runner/DebugProfile.entitlements mobile/macos/Runner/Release.entitlements`
- `flutter analyze`
- `flutter test`
- `flutter test -d flutter-tester integration_test/app_smoke_test.dart`
- `flutter build apk --debug`
- `flutter build apk --release` without `mobile/android/key.properties`: failed intentionally with `Release signing is not configured`
- `flutter build appbundle --release` without `mobile/android/key.properties`: failed intentionally with `Release signing is not configured`
- `flutter build apk --release` with a temporary test keystore: built `build/app/outputs/flutter-apk/app-release.apk`
- `flutter build appbundle --release` with a temporary test keystore: built `build/app/outputs/bundle/release/app-release.aab`
- `flutter build ios --simulator --debug`
- XcodeBuildMCP `build_run_sim` on iPhone 17 simulator
- XcodeBuildMCP screenshot confirmed the app launched to the native server configuration screen
- `flutter build ios --no-codesign`
- `flutter build macos --debug`
- `flutter build macos --release`

## Environment Notes

- The default Android SDK path was unusable because it pointed at Homebrew `platform-tools`. Local validation used `/opt/homebrew/share/android-commandlinetools`.
- `sdkmanager` was blocked by a stale Android user-home cache under `/Volumes/1t`; validation used `ANDROID_USER_HOME=/private/tmp/sky-ledger-android-user-home`.
- Gradle was blocked by a stale home under `/Volumes/1t`; validation used `GRADLE_USER_HOME=/private/tmp/sky-ledger-gradle-home`.
- iOS simulator validation initially failed because no simulator runtime was installed. `xcodebuild -downloadPlatform iOS` installed iOS 26.4.1 simulator runtime, after which simulator build and launch succeeded.

## Remaining Constraints

- Android production artifacts still require a real release keystore. The temporary test keystore used here was deleted and must not be used for release.
- iOS device/App Store distribution still requires real Apple signing and provisioning. `flutter build ios --no-codesign` only proves the unsigned device build compiles.
- macOS release build compiles, but public distribution still needs a signing and notarization pass before it should be published.
