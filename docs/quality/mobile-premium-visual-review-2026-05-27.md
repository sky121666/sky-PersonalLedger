# Mobile Premium Visual Review - 2026-05-27

## Conclusion

The premium mobile target screens pass automated light/dark visual smoke coverage, a human screenshot review on the exported macOS artifacts, and a focused semantics/tap-target test pass. One light-mode Quick Transaction contrast issue was found and fixed by giving the embedded sheet a theme surface background instead of a transparent root. A second accessibility issue was found and fixed by raising themed `IconButton` minimum targets to 48 px.

This review does not replace final iOS/Android release-device QA. It verifies visual structure, readability, and obvious overflow issues from the current screenshot set.

## Reviewed Evidence

| Screen | Light | Dark | Result |
| --- | --- | --- | --- |
| Home dashboard top | `/tmp/personal-ledger-premium-screenshots/home-dashboard-top-light.png` | `/tmp/personal-ledger-premium-screenshots/home-dashboard-top-dark.png` | PASS |
| Home dashboard family/budget | `/tmp/personal-ledger-premium-screenshots/home-dashboard-family-budget-light.png` | `/tmp/personal-ledger-premium-screenshots/home-dashboard-family-budget-dark.png` | PASS |
| Quick transaction form | `/tmp/personal-ledger-premium-screenshots/quick-transaction-form-light.png` | `/tmp/personal-ledger-premium-screenshots/quick-transaction-form-dark.png` | PASS after fix |
| AI reports expanded | `/tmp/personal-ledger-premium-screenshots/ai-reports-expanded-light.png` | `/tmp/personal-ledger-premium-screenshots/ai-reports-expanded-dark.png` | PASS |
| Family hub summary | `/tmp/personal-ledger-premium-screenshots/family-hub-summary-light.png` | `/tmp/personal-ledger-premium-screenshots/family-hub-summary-dark.png` | PASS |

## Findings

| Priority | Area | Finding | Status | Evidence |
| --- | --- | --- | --- | --- |
| P1 | Quick Transaction light mode | Embedded form title and close button inherited a black outer background while using dark text, making them hard to read. | FIXED | `mobile/lib/features/transactions/presentation/quick_transaction_page.dart` now uses `Theme.of(context).colorScheme.surface` for the embedded root `Material`. |
| P1 | Premium icon buttons | AI Reports and Family Hub app-bar icon buttons measured 40 px in widget tests, below the 44 pt/dp minimum target. | FIXED | `mobile/lib/app/theme/app_theme.dart` now sets `IconButtonThemeData` with a 48 px minimum size for light and dark themes. |
| P2 | Device-native screenshots | Current exported artifacts are generated from the macOS integration target, not native iOS/Android screenshot capture. | OPEN | iOS Simulator and Android Emulator smoke tests pass, but release-note screenshots should be captured from those targets if needed. |
| P2 | iOS/Android release-device QA | Current visual evidence does not include a USB-connected iPhone run or Android release-device emulator release QA evidence. | OPEN | Requires USB iPhone execution plus Android emulator E2E or signed-install manual evidence before public distribution. |

## Manual Review Notes

| Area | Result |
| --- | --- |
| Overflow | No visible text or component overflow in reviewed screenshots. |
| Density | Home, AI Reports, and Family Hub use readable spacing. Quick Transaction is dense but acceptable for a bottom-sheet form. |
| Contrast | Light/dark contrast is acceptable after the Quick Transaction embedded background fix. |
| Safe area | Top bars and bottom action areas are visible in the exported frames. iOS and Android release devices still need final safe-area/status-bar/navigation-bar confirmation. |
| Tap targets | Primary buttons, icon buttons, and form controls appear large enough for mobile use. |
| Motion | Screenshots cannot prove frame pacing; automated smoke verifies no thrown visual-frame exceptions. |
| Semantics | Premium Home, Quick Transaction, AI Reports, and Family Hub have a focused semantics/tap-target widget test. |

## Verification

| Command | Result |
| --- | --- |
| `flutter test integration_test/premium_screens_smoke_test.dart` | PASS, 8 light/dark premium cases |
| `flutter test -d macos integration_test/premium_screens_smoke_test.dart --dart-define=LEDGER_PREMIUM_SCREENSHOT_DIR=/tmp/personal-ledger-premium-screenshots` | PASS, 10 PNG screenshots exported |
| `flutter test test/premium_accessibility_test.dart` | PASS, premium semantic labels, tooltips, visible form labels, and 44+ px key tap targets |
| `flutter analyze` | PASS |
| `flutter test` | PASS, 192 tests |

## Remaining Release Review

1. Run the same premium flows on a USB-connected iPhone and an Android emulator before public distribution.
2. Capture device-native screenshots from iOS Simulator and Android Emulator if release materials require exact platform frames.
3. Run a real VoiceOver/TalkBack pass before public distribution if accessibility quality is a release criterion.
