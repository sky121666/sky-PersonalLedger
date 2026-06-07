# Android UI gate - 2026-06-08

- Device: `emulator-5554` (`sdk_gphone64_arm64`, Android emulator)
- Local backend: `http://127.0.0.1:8080`
- Android backend URL entered: `http://10.0.2.2:8080`
- Install command: `FLUTTER_BIN=$(command -v flutter) LEDGER_E2E_LOCAL_SERVER_URL=http://127.0.0.1:8080 ./QA/android_install.sh emulator-5554`
- Screenshot test: `flutter test integration_test/premium_screens_smoke_test.dart -d emulator-5554 --dart-define=LEDGER_PREMIUM_SCREENSHOT_DIR=/Users/sky/项目/sky-PersonalLedger/mobile/QA/screenshots/android --plain-name 'renders premium quick transaction sheet form (light)'`

## Evidence

- App launch: `mobile/QA/screenshots/android/android-app-launch-20260608.png`
- Server URL filled: `mobile/QA/screenshots/android/android-server-address-filled-20260608.png`
- Login after entering ledger: `mobile/QA/screenshots/android/android-after-enter-ledger-20260608.png`

## Runtime result

- The Android emulator booted and stayed online.
- The app installed and launched successfully.
- The app accepted the current local backend address through the emulator bridge.
- Login screen rendered after entering the ledger address.
- Local runtime files under ignored `mobile/QA/runtime/` recorded `gfxinfo`, logcat, tap-chain note, and UI dump for this run.
- `gfxinfo` on the login screen reported 64 frames, 6 janky frames (9.38%), P50 16ms, P90 20ms, P95 28ms, P99 57ms.
- Logcat did not show `FATAL EXCEPTION`, `AndroidRuntime`, app process crash, or ANR markers for `com.skyapp.personal_ledger`.

## Boundary

- Full authenticated Android page traversal is still not claimed in this report because no real ledger password was provided in this run.
