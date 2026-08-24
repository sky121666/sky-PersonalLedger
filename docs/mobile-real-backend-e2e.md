# Mobile Real Backend E2E

This project uses `scripts/verify-mobile-e2e.sh` to validate the mobile app against a real local Go backend. The script starts an isolated SQLite backend on a random local port, sets the first access password, creates an account, creates/edits/deletes a transaction, and verifies the visible ledger state.

## Default local check

Run from the repository root:

```bash
./scripts/verify-mobile-e2e.sh
```

The default target is `flutter-tester`. It is fast and does not require an Android emulator or iOS simulator, but it still exercises the real backend API and auth flow.

## Android emulator check

```bash
RUN_FLUTTER_TESTER_E2E=0 RUN_ANDROID_E2E=1 ./scripts/verify-mobile-e2e.sh
```

默认链路会优先选择 `emulator-*` 设备；如果你当前未启动模拟器，可显式带上：

```bash
ANDROID_PREFER_EMULATOR=1 RUN_FLUTTER_TESTER_E2E=0 RUN_ANDROID_E2E=1 ./scripts/verify-mobile-e2e.sh
```

该链路已按 Android Emulator 为默认策略；请保持 `ANDROID_PREFER_EMULATOR=1`（默认）。脚本会在未检测到 emulator 时自动尝试启动并阻断非模拟器路径。

For quick Android UI gating, run the shorter smoke flow instead of the full ledger mutation E2E:

```bash
ANDROID_PREFER_EMULATOR=1 \
RUN_FLUTTER_TESTER_E2E=0 \
RUN_ANDROID_E2E=1 \
LEDGER_MOBILE_E2E_TEST_FILE=integration_test/app_real_backend_smoke_test.dart \
./scripts/verify-mobile-e2e.sh
```

Use the full E2E for `flutter-tester` first, then use Android smoke for emulator install, launch, auth, and quick-transaction entry coverage.

The script looks for a complete Android SDK under `ANDROID_SDK_ROOT`, `ANDROID_HOME`, `/opt/homebrew/share/android-commandlinetools`, or `$HOME/Library/Android/sdk`. If no emulator is already running, it creates a temporary AVD from `ANDROID_E2E_SYSTEM_IMAGE`.

On Apple Silicon local machines the default image is:

```bash
system-images;android-35;google_apis;arm64-v8a
```

On GitHub-hosted Linux runners the manual Android workflow uses:

```bash
system-images;android-35;google_apis;x86_64
```

## iOS simulator check

```bash
RUN_FLUTTER_TESTER_E2E=0 RUN_IOS_E2E=1 ./scripts/verify-mobile-e2e.sh
```

The script selects `iPhone 17` when available, otherwise the first available iPhone simulator. If the script boots a simulator itself, it shuts that simulator down during cleanup.

For quick iOS UI gating, use the same smoke flow:

```bash
RUN_FLUTTER_TESTER_E2E=0 \
RUN_IOS_E2E=1 \
LEDGER_MOBILE_E2E_TEST_FILE=integration_test/app_real_backend_smoke_test.dart \
./scripts/verify-mobile-e2e.sh
```

Native cold builds can take longer than the default 900 seconds. Set
`LEDGER_MOBILE_E2E_TIMEOUT_SECONDS` to raise both the outer process timeout and the
Flutter test-case timeout together, for example:

```bash
LEDGER_MOBILE_E2E_TIMEOUT_SECONDS=1800 \
RUN_FLUTTER_TESTER_E2E=0 RUN_IOS_E2E=1 \
./scripts/verify-mobile-e2e.sh
```

## CI coverage

`.github/workflows/mobile-e2e.yml` runs the real-backend `flutter-tester` path on GitHub push and pull request events that touch backend, mobile, or the E2E script. The workflow is guarded with `github.server_url == 'https://github.com'` so Forgejo does not execute GitHub-specific jobs.

`.github/workflows/mobile-platform-e2e.yml` has manual `workflow_dispatch` targets for Android emulator and iOS simulator checks. They are intentionally opt-in because platform runners are slower and more sensitive to SDK/runtime availability.

## Notes

- The backend always runs with isolated SQLite state under a temporary directory.
- `LEDGER_SETUP_CONFIG_PATH` is pointed at the same temporary directory so setup writes do not touch local or container config.
- Android uses `http://10.0.2.2:<port>` to reach the host backend from the emulator.
- iOS and `flutter-tester` use `http://127.0.0.1:<port>`.
