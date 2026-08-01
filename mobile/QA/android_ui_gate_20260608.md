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

## 2026-06-08 00:51 Retest

- Backend check: `curl http://127.0.0.1:8080/api/v1/auth/status` returned `initialized=true`.
- AVD: `pld-emu-2`, serial `emulator-5554`.
- Install command: `FLUTTER_BIN=$(command -v flutter) LEDGER_E2E_LOCAL_SERVER_URL=http://127.0.0.1:8080 ./mobile/QA/android_install.sh emulator-5554`.
- Package: `com.skyapp.personal_ledger`, activity `.MainActivity`.
- App launch screenshot: `mobile/QA/screenshots/android/android-profile-theme-20260608-005122.png`.
- Login screenshot after entering `http://10.0.2.2:8080`: `mobile/QA/screenshots/android/android-after-enter-local-20260608-005204.png`.
- Result: Android Emulator install, launch, local-backend address entry, and transition to ledger login passed.
- Boundary: authenticated traversal is still not claimed because the current local ledger is already initialized and the plaintext password is unknown.

## 2026-06-08 01:12 Clean Auth Entry Retest

- AVD: `pld-emu-2`, serial `emulator-5554`.
- Install command: `FLUTTER_BIN=$(command -v flutter) LEDGER_E2E_LOCAL_SERVER_URL=http://127.0.0.1:8080 ./mobile/QA/android_install.sh emulator-5554`.
- App launch screenshot: `mobile/QA/screenshots/android/android-auth-entry-clean-20260608-011232.png`.
- Login screenshot after entering `http://10.0.2.2:8080`: `mobile/QA/screenshots/android/android-login-entry-clean-20260608-011259.png`.
- UI tree result: connection screen exposed `连接账本`, `账本地址`, `进入账本`; login screen exposed `账本解锁`, `登录`, `更换账本`.
- Result: latest Android build keeps the clean auth/server entry layout and reaches the local-backend login page.
- Boundary: authenticated traversal remains unclaimed because the current local ledger password is unknown.

## 2026-06-08 01:23 Emulator Runtime Address Retest

- AVD: `pld-emu-2`, serial `emulator-5554`.
- Backend check: `http://127.0.0.1:8080/api/v1/auth/status` returned `initialized=true`.
- Install command: `FLUTTER_BIN=$(command -v flutter) LEDGER_E2E_LOCAL_SERVER_URL=http://127.0.0.1:8080 ./mobile/QA/android_install.sh emulator-5554`.
- Script behavior: detected local backend, converted emulator URL to `http://10.0.2.2:8080`, built debug APK with `LEDGER_E2E_SERVER_URL`, then installed the prebuilt APK.
- Login screenshot: `mobile/QA/screenshots/android/android-emulator-login-local-server-20260608.png`.
- UI tree result: login screen exposed `账本解锁`, `登录`, `http://10.0.2.2:8080`, and `更换账本`.
- Result: Android emulator no longer requires manually retyping the current local backend address after install.
- Boundary: authenticated traversal remains unclaimed because the current local ledger password is unknown.

## 2026-06-08 01:52 Emulator-Only Install Retest

- AVD: `pld-emu-2`, serial `emulator-5554`.
- Backend check: `http://127.0.0.1:8080/api/v1/auth/status` returned `initialized=true`.
- Script policy: `mobile/QA/android_install.sh` now defaults to `ANDROID_PREFER_EMULATOR=1`, filters online targets to `emulator-*`, rejects non-emulator Android targets unless explicitly overridden, and starts AVDs with detached stdio.
- Install command: `FLUTTER_BIN=$(command -v flutter) LEDGER_E2E_LOCAL_SERVER_URL=http://127.0.0.1:8080 ./mobile/QA/android_install.sh emulator-5554`.
- Script behavior: converted the host URL to `http://10.0.2.2:8080`, built a debug APK with `LEDGER_E2E_SERVER_URL`, and installed it on the Android emulator.
- Launch screenshot: `mobile/QA/screenshots/android/android-emulator-install-launch-settled-20260608.png`.
- Runtime result: app process stayed alive after settling, and the login screen showed `账本解锁`, `登录`, `http://10.0.2.2:8080`, and `更换账本`.
- Logcat check: no `FATAL EXCEPTION`, `AndroidRuntime` crash, or ANR marker was observed for `com.skyapp.personal_ledger` during the launch window.
- Boundary: authenticated traversal remains unclaimed because the current local ledger password is unknown.
