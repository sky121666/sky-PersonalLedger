# Smart Quick Ledger Android Evidence - 2026-06-15

## Scope

- Android `NotificationListenerService` registration and permission entry.
- WeChat-style notification parsing into a local pending draft.
- Flutter smart quick ledger permission state, source switches, pending draft loading, and confirm-to-transaction flow.
- Android emulator validation against an isolated local SQLite backend.

## Runtime Evidence

- Emulator: `pld-emu`, serial `emulator-5554`.
- Backend: isolated local Go backend, Android URL `http://10.0.2.2:60031`.
- Password used for isolated test backend: `LedgerE2ePass123!`.
- Debug notification injection:
  - action `com.skyapp.personal_ledger.DEBUG_SMART_QUICK_LEDGER`
  - package `com.tencent.mm`
  - title `微信支付`
  - text `付款给瑞幸咖啡38.90元`
- Native store wrote a pending draft with source `微信支付`, type `expense`, amount `38.9`, confidence `0.88`.
- Smart quick ledger page showed `Android 已开启` and `待确认 1 条`.
- Confirming the draft dismissed the pending queue and created a real transaction visible in `明细`.

## Screenshots

- `mobile/QA/screenshots/android/android-smart-quick-ledger-final-20260615.png`
- `mobile/QA/screenshots/android/android-smart-quick-ledger-notification-enabled-20260615.png`
- `mobile/QA/screenshots/android/android-smart-quick-ledger-transaction-20260615.png`

## Commands

```bash
cd /Users/sky/项目/sky-PersonalLedger/mobile
flutter test test/ui_pollution_guard_test.dart test/profile_widget_test.dart test/smart_quick_ledger_widget_test.dart --reporter compact
flutter analyze

cd /Users/sky/项目/sky-PersonalLedger/mobile/android
./gradlew :app:testDebugUnitTest --tests 'com.skyapp.personal_ledger.PaymentNotificationParserTest' --console=plain
./gradlew :app:assembleDebug --console=plain
```

## Result

PASS. The feature is no longer a static screen: Android native notification parsing, local draft persistence, Flutter draft loading, permission status refresh, and confirm-to-ledger behavior were verified in the Android emulator.
