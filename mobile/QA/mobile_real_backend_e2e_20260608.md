# Mobile real backend E2E - 2026-06-08

## Scope

This note records the mobile real-backend verification after the simplified mobile UI and auth entry flow changes.

The backend used in these checks is isolated SQLite state created under `mktemp`; it does not use the local persistent `data/ledger.db`.

## Fix

Updated the real-backend integration tests to match the current mobile auth state machine:

- Runtime `LEDGER_E2E_SERVER_URL` can move the app directly from bootstrap to setup/login.
- Tests now accept server config, setup, login, or authenticated home as valid entry states.
- Tests only type the server URL when the server config form is actually visible.
- Material AppBar navigation is handled without assuming a Cupertino back button.
- Profile return checks use the current page title `功能` instead of relying only on the bottom-tab label `我的`.

## Verification

Passed:

```bash
./scripts/verify-mobile-e2e.sh
```

Result:

- Started isolated Go backend with SQLite.
- Set temporary ledger password.
- Opened the Flutter mobile app on `flutter-tester`.
- Connected to the backend.
- Created an account.
- Created, edited, and deleted an expense transaction.
- Verified visible transaction and balance states.
- Final result: `All tests passed!`

Passed on Android Emulator:

```bash
ANDROID_PREFER_EMULATOR=1 \
RUN_FLUTTER_TESTER_E2E=0 \
RUN_ANDROID_E2E=1 \
LEDGER_MOBILE_E2E_TEST_FILE=integration_test/app_real_backend_smoke_test.dart \
./scripts/verify-mobile-e2e.sh
```

Result:

- Started isolated Go backend with SQLite.
- Selected Android emulator `emulator-5554`.
- Built and installed the debug APK.
- Connected from Android to the host backend through the emulator bridge.
- Completed setup/login.
- Opened the quick transaction form from the main shell `+` action.
- Final result: `All tests passed!`

Passed on iOS Simulator:

```bash
RUN_FLUTTER_TESTER_E2E=0 \
RUN_IOS_E2E=1 \
LEDGER_MOBILE_E2E_TEST_FILE=integration_test/app_real_backend_smoke_test.dart \
./scripts/verify-mobile-e2e.sh
```

Result:

- Started isolated Go backend with SQLite.
- Selected `iPhone 17` Simulator.
- Built and launched the iOS app.
- Completed setup/login.
- Opened the quick transaction form from the main shell `+` action.
- Final result: `All tests passed!`

Passed:

```bash
flutter test -d flutter-tester \
  --dart-define="LEDGER_E2E_SERVER_URL=http://127.0.0.1:<isolated-port>" \
  --dart-define="LEDGER_E2E_PASSWORD=LedgerE2ePass123!" \
  integration_test/app_real_backend_smoke_test.dart --reporter compact
```

Result:

- Connected to the isolated backend.
- Completed setup/login.
- Opened the quick transaction form.
- Final result: `All tests passed!`

Passed:

```bash
flutter analyze
```

Result:

- `No issues found!`

## Boundary

This closes the real-backend `flutter-tester` regression gap and adds stable Android/iOS simulator smoke gates for install/build, auth, and quick transaction entry.

The full Android ledger mutation E2E was attempted, but it is too slow and brittle for this UI acceptance gate. Keep the full mutation flow on `flutter-tester`; use Android smoke for emulator install, launch, auth, and primary `+` interaction coverage.
