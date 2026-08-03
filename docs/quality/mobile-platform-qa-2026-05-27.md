# Mobile Platform QA Report - 2026-05-27

## Conclusion

The mobile premium modernization is now build-verified at the Flutter, iOS simulator artifact, Android debug APK, macOS smoke integration-test, iOS Simulator smoke integration-test, and Android Emulator smoke integration-test levels. The premium target screens are also covered by a mocked-data integration smoke test on macOS, iPhone 17 Simulator, and Android API 35 Emulator, with local PNG screenshot export available for visual review.

The real-backend E2E path now passes on Flutter tester, iOS Simulator, and Android Emulator. The premium visual smoke path now covers light and dark themes with exported screenshot evidence, the exported screenshots have been manually reviewed, and the premium screens now have a focused semantics/tap-target test pass. Android native real-backend E2E was reconfirmed by GitHub Actions run `30776159138` on 2026-08-03, and iOS Simulator native real-backend E2E was reconfirmed by run `30775889356`. The remaining release-quality gap is physical iPhone QA, the full manual device checklist, and real VoiceOver/TalkBack review.

## Environment

| Item | Result |
| --- | --- |
| Flutter | 3.35.7 stable |
| Dart | 3.9.2 |
| Xcode | 26.5 |
| CocoaPods | 1.16.2 |
| Connected Flutter devices | iPhone 17 Simulator, macOS, Chrome |
| Wireless mobile device | `sky的iPhone 12`, iOS 26.5 |
| Android SDK usable path | `/opt/homebrew/share/android-commandlinetools` |
| Global Android env | FIXED in `~/.zprofile` and `~/.zshrc`; new shells resolve SDK tools under `/opt/homebrew/share/android-commandlinetools` |
| Temporary Android AVD | `personal_ledger_api35`, API 35 Google APIs ARM64, created under `/tmp` |

## Passed Gates

| Gate | Command | Result |
| --- | --- | --- |
| iOS simulator build | `flutter build ios --simulator --debug` | PASS, built `build/ios/iphonesimulator/Runner.app` |
| Android debug APK build | `ANDROID_HOME=/opt/homebrew/share/android-commandlinetools ANDROID_SDK_ROOT=/opt/homebrew/share/android-commandlinetools ANDROID_USER_HOME="$PWD/.android-user-home" ANDROID_AVD_HOME="$PWD/.android-avd" GRADLE_USER_HOME="$PWD/.gradle" flutter build apk --debug` | PASS, built `build/app/outputs/flutter-apk/app-debug.apk` |
| macOS smoke integration test | `flutter test -d macos integration_test/app_smoke_test.dart` | PASS |
| iOS Simulator smoke integration test | `flutter test -d C417531C-3ABC-4357-880C-4ECC9A1752D1 integration_test/app_smoke_test.dart` | PASS on iPhone 17 Simulator |
| Android Emulator smoke integration test | `ANDROID_HOME=/opt/homebrew/share/android-commandlinetools ANDROID_SDK_ROOT=/opt/homebrew/share/android-commandlinetools ANDROID_USER_HOME="$PWD/.android-user-home" ANDROID_AVD_HOME="$PWD/.android-avd" GRADLE_USER_HOME="$PWD/.gradle" PATH=/opt/homebrew/share/android-commandlinetools/platform-tools:$PATH flutter test -d emulator-5554 integration_test/app_smoke_test.dart` | PASS on temporary API 35 emulator |
| Premium target screens smoke test | `flutter test integration_test/premium_screens_smoke_test.dart` | PASS, 8 target screen cases across light and dark themes; each case checks for a stable visual frame before screenshot capture |
| Premium target screens screenshot export | `flutter test -d macos integration_test/premium_screens_smoke_test.dart --dart-define=LEDGER_PREMIUM_SCREENSHOT_DIR=/tmp/personal-ledger-premium-screenshots` | PASS, exported 10 PNG files: Home top, Home family/budget, Quick Transaction, AI Reports, and Family Hub in light and dark themes |
| Premium target screens visual review | `docs/quality/mobile-premium-visual-review-2026-05-27.md` | PASS after fix; reviewed 10 exported screenshots, found and fixed a Quick Transaction light-mode contrast issue |
| Premium accessibility semantics | `flutter test test/premium_accessibility_test.dart` | PASS, covers premium Home, Quick Transaction, AI Reports, and Family Hub semantic labels/tooltips/form labels and 44+ px key tap targets |
| Premium target screens iOS Simulator test | `flutter test -d C417531C-3ABC-4357-880C-4ECC9A1752D1 integration_test/premium_screens_smoke_test.dart` | PASS on iPhone 17 Simulator, 4 target screen cases |
| Premium target screens Android Emulator test | `ANDROID_HOME=/opt/homebrew/share/android-commandlinetools ANDROID_SDK_ROOT=/opt/homebrew/share/android-commandlinetools ANDROID_USER_HOME="$PWD/.android-user-home" ANDROID_AVD_HOME="$PWD/.android-avd" GRADLE_USER_HOME="$PWD/.gradle" PATH=/opt/homebrew/share/android-commandlinetools/platform-tools:$PATH flutter test -d emulator-5554 integration_test/premium_screens_smoke_test.dart` | PASS on temporary API 35 emulator, 4 target screen cases |
| Real backend E2E on Flutter tester | `RUN_FLUTTER_TESTER_E2E=1 RUN_ANDROID_E2E=0 RUN_IOS_E2E=0 ./scripts/verify-mobile-e2e.sh` | PASS, isolated SQLite backend with auth, account, transaction create/edit/delete, and balance verification |
| Real backend E2E on iOS Simulator | `RUN_FLUTTER_TESTER_E2E=0 RUN_ANDROID_E2E=0 RUN_IOS_E2E=1 ./scripts/verify-mobile-e2e.sh` | PASS on iOS Simulator, isolated SQLite backend with auth, account, transaction create/edit/delete, and balance verification |
| Real backend E2E on Android Emulator | `RUN_FLUTTER_TESTER_E2E=0 RUN_ANDROID_E2E=1 RUN_IOS_E2E=0 LEDGER_MOBILE_E2E_TIMEOUT_SECONDS=900 ./scripts/verify-mobile-e2e.sh` from a fresh `zsh -lc` environment | PASS on `emulator-5554`; debug APK built in 25.7s, installed, and completed the real-backend ledger entry flow with the fixed global Android environment |
| Mobile E2E timeout guard | `RUN_FLUTTER_TESTER_E2E=1 RUN_ANDROID_E2E=0 RUN_IOS_E2E=0 LEDGER_MOBILE_E2E_TIMEOUT_SECONDS=180 ./scripts/verify-mobile-e2e.sh` | PASS; verifies the E2E timeout wrapper does not break the stable Flutter tester path |
| Flutter doctor | `zsh -lc 'flutter doctor -v'` | PASS; Flutter, Android toolchain, Xcode, Chrome, Android Studio, connected devices, and network resources all show no issues |
| Mobile analyzer | `flutter analyze` | PASS |
| Mobile tests | `flutter test` | PASS, 192 tests |

## Blocked Or Not Fully Proved

| Gate | Status | Evidence | Required Follow-up |
| --- | --- | --- | --- |
| iPhone 12 integration test | BLOCKED | `flutter test -d 00008101-000549C936C0001E integration_test/app_smoke_test.dart` fails: wireless iOS device cannot start app for integration test | Connect by cable or run with a supported published-port workflow |
| Android cold Gradle cache behavior | PARTIAL | A per-run temporary `GRADLE_USER_HOME` timed out after 420s at `Running Gradle task 'assembleDebug'`; using project-local ignored `mobile/.gradle` completed Android real-backend E2E successfully | Keep `mobile/.gradle` as the default isolated local cache and preserve the timeout diagnostics for future cold-cache failures |
| Device-native premium-screen captures | PARTIAL | Current iPhone 17 Pro Simulator evidence covers Home, Transactions, Statistics, Features, and Quick Entry under `mobile/QA/design/final-audit-20260803/`; data-management and API-token surfaces retain 800×600 component evidence | Capture the remaining deep settings surfaces on an iPhone-sized target and repeat on a physical iPhone if release materials require device-native frames |

## Manual Visual QA Checklist

Run this on both iOS and Android before a release candidate.

| Area | Required Checks |
| --- | --- |
| Home | Premium surfaces render without overflow; family card opens Family Hub; refresh does not jump layout |
| Quick transaction | Bottom sheet respects safe area; keyboard does not hide save action; amount autofocus works; save loading state is clear |
| AI reports | Empty, generating, completed, failed, expanded sections render clearly; raw API keys are never shown |
| Family Hub | Summary total, ranking, default member, disabled member, and empty state are understandable |
| Dark mode | Card contrast, text contrast, semantic green/red/yellow, dividers, and status chips remain readable |
| Small screen | No horizontal overflow at 375 px width; long member names and provider/model labels wrap or truncate cleanly |
| Reduced motion | Motion collapses or softens when platform reduced-motion is enabled |
| Accessibility | Primary tap targets are at least 44 pt / 48 dp; icon-only actions have tooltips or labels |
| Performance | Opening quick transaction and expanding AI report cards should stay visually smooth; no continuous decorative animation loops |

## Release Readiness Score

| Dimension | Score | Reason |
| --- | ---: | --- |
| Functional coverage | 96/100 | Family, AI, quick entry, and home paths have widget tests, target-screen integration smoke evidence, and real-backend E2E on Flutter tester/iOS Simulator/Android Emulator |
| Mobile visual system | 97/100 | Shared premium surfaces/motion are applied to target screens, device smoke passes, light/dark local PNG screenshot export exists, exported screenshots have a documented human review, and premium semantics/tap targets are tested |
| iOS readiness | 94/100 | iOS simulator build, boot smoke, premium target screens, and real-backend E2E pass; physical iPhone test still blocked by wireless launch limitation |
| Android readiness | 97/100 | APK build, boot smoke, premium target screen smoke, real-backend E2E, and `flutter doctor` pass with corrected global SDK env |
| Release confidence | 98/100 | Strong automated, simulator/emulator, Android real-backend, fixed Android environment, light/dark screenshot-export, visual-review, and semantics evidence; still short of physical iPhone and optional real screen-reader review |

Overall current mobile release-readiness: **98/100**.

## Next Required Evidence For 99+

1. Connect iPhone by cable or use a supported published-port workflow, then run `integration_test/app_smoke_test.dart` on the physical device.
2. Capture Data Management and API Token directly on an iPhone-sized target; add Android device-native frames if release notes require them.
3. Run a real VoiceOver/TalkBack pass if public accessibility quality is a release criterion.
4. For CI or brand-new machines, run Android E2E once with the project-local Gradle cache warmed, or keep the timeout diagnostics enabled to surface cold-cache stalls cleanly.

Physical-device preflight command:

```bash
REQUIRE_PHYSICAL_IOS=1 ./scripts/check-mobile-device-qa-preflight.sh
```
