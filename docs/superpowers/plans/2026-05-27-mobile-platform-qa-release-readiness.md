# Mobile Platform QA And Release Readiness Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the mobile premium modernization with platform-level QA evidence for iOS and Android, plus a release-readiness checklist that makes remaining device-dependent gaps explicit.

**Architecture:** Keep this phase focused on verification and readiness. Do not change backend contracts, data models, Web behavior, or mobile product scope unless a platform gate exposes a concrete defect.

**Tech Stack:** Flutter, iOS/Xcode simulator build, Android toolchain/APK build when available, existing widget/integration tests.

---

## Environment Baseline

- [x] **Step 1: Inspect Flutter environment**

Run:

```bash
cd mobile && flutter --version && flutter devices && flutter doctor -v
```

Observed:

- Flutter 3.35.7 / Dart 3.9.2.
- Xcode 26.5 and CocoaPods 1.16.2 are available.
- Connected Flutter devices are macOS and Chrome only.
- Android toolchain is incomplete because `cmdline-tools` is missing.
- No Android AVD or iOS Simulator is currently available through `flutter emulators`.
- A wireless iPhone 12 is discovered but not connected/unlocked for development.

## Task 1: iOS Build Gate

- [x] **Step 1: Build iOS simulator artifact**

Run:

```bash
cd mobile && flutter build ios --simulator --debug
```

Expected: PASS if iOS build settings and Pods are valid.

## Task 2: Android Build Gate

- [x] **Step 1: Build Android debug APK**

Run:

```bash
cd mobile && flutter build apk --debug
```

Expected: PASS if Android SDK command-line tools and Gradle setup are valid. If blocked by local SDK setup, document the exact missing toolchain item.

## Task 3: Integration Test Gate

- [x] **Step 1: Inspect available integration tests**

Current integration tests:

- `mobile/integration_test/app_smoke_test.dart`
- `mobile/integration_test/app_real_backend_e2e_test.dart`

- [x] **Step 2: Run what can be run without a mobile device**

If no simulator/emulator exists, do not claim device E2E completion. Record the blocker and keep widget/analyzer/build gates as current evidence.

## Task 4: Release Readiness Document

- [x] **Step 1: Add platform QA report**

Create `docs/quality/mobile-platform-qa-2026-05-27.md` with:

- Passed commands.
- Blocked commands and exact environment reason.
- iOS/Android manual visual checklist.
- Accessibility, reduced-motion, keyboard, dark-mode, and small-screen checklist.
- Release readiness score and remaining gaps.

## Task 5: Final Verification

- [x] **Step 1: Run analyzer**

Run:

```bash
cd mobile && flutter analyze
```

- [x] **Step 2: Run all mobile tests**

Run:

```bash
cd mobile && flutter test
```

- [x] **Step 3: Run whitespace check**

Run:

```bash
git diff --check
```
