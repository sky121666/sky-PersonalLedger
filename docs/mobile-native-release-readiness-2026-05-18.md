# Mobile Native Release Readiness - 2026-05-18

## Status

Release-acceptable for the current Android native scope.

Score: 100/100 for Android simulator validation.

## Commits Included

- `d588a6d test: complete category and tag native states`
- `2ee0f88 test: complete template and account log native states`
- `6d0e3c3 test: complete report home statistics states`
- `f7656ca test: complete native shell navigation`
- `81ad23e fix: polish native release readiness`
- `f1943a4 fix: close native smoke regressions`

## Verification

Completed:

- `./scripts/verify-clean-checkout.sh`
- `cd backend && go test ./...`
- `cd mobile && flutter analyze`
- `cd mobile && flutter test`
- `cd mobile && ANDROID_HOME=/Volumes/1t/Android/sdk ANDROID_SDK_ROOT=/Volumes/1t/Android/sdk GRADLE_USER_HOME=/Volumes/1t/Android/gradle-home flutter test integration_test/app_smoke_test.dart -d emulator-5554`
- `cd mobile && ANDROID_HOME=/Volumes/1t/Android/sdk ANDROID_SDK_ROOT=/Volumes/1t/Android/sdk GRADLE_USER_HOME=/Volumes/1t/Android/gradle-home flutter build apk --release`

Flutter widget tests: 155.

Android release APK:

- `mobile/build/app/outputs/flutter-apk/app-release.apk`
- Size: 56.2 MB

## Runtime Smoke Evidence

Android emulator:

- Device: `emulator-5554`
- AVD: `AutoX_API35_1t`
- SDK path: `/Volumes/1t/Android/sdk`
- Gradle home: `/Volumes/1t/Android/gradle-home`
- Backend URL inside emulator: `http://10.0.2.2:8080`

Validated flows:

- Startup and server configuration.
- Login with local test user.
- Home dashboard.
- Quick transaction creation.
- Transaction list local-time display.
- Statistics daily grouping.
- Lending page.
- Reminder/debt page.
- Notification settings with token refresh.

Smoke screenshots captured during validation:

- `/tmp/sky-ledger-smoke-profile.png`
- `/tmp/sky-ledger-smoke-home.png`
- `/tmp/sky-ledger-smoke-quick-transaction-fixed.png`
- `/tmp/sky-ledger-smoke-transaction-created-fixed2.png`
- `/tmp/sky-ledger-smoke-transactions-time-fixed2.png`
- `/tmp/sky-ledger-smoke-statistics-day-fixed.png`
- `/tmp/sky-ledger-smoke-lending.png`
- `/tmp/sky-ledger-smoke-reminders.png`
- `/tmp/sky-ledger-smoke-notifications-fixed.png`

## Smoke Regressions Fixed

- `GET /api/v1/tags` now returns the unified response envelope expected by mobile.
- Transaction creation accepts Flutter local ISO date strings.
- Daily statistics group by the local date substring instead of SQLite UTC conversion.
- Mobile transaction list parses backend date strings as local time.
- Expired JWT now returns `40102 token expired`, allowing mobile token refresh instead of surfacing `invalid token`.

## Caveats

- iOS simulator validation was not completed on this machine because the simulator environment was unavailable.
- Android release currently uses the debug signing config. This is acceptable for installable release-candidate validation, but a production release must use a real signing key.
- The release APK is a generated artifact and is intentionally not tracked by git.

## Release Gate

Before publishing a production artifact, rerun:

```bash
./scripts/verify-clean-checkout.sh
cd mobile && ANDROID_HOME=/Volumes/1t/Android/sdk ANDROID_SDK_ROOT=/Volumes/1t/Android/sdk GRADLE_USER_HOME=/Volumes/1t/Android/gradle-home flutter build apk --release
git status --short
```
