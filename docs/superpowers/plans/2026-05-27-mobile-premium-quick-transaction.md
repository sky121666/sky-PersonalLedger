# Mobile Premium Quick Transaction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade the mobile quick transaction flow into a premium, fast bottom-sheet experience without changing transaction business rules.

**Architecture:** Keep the existing transaction repository, attachment handling, family member handling, and validation intact. Refactor only the Flutter presentation layer to use the premium motion primitives from the Foundation phase.

**Tech Stack:** Flutter, Material 3, Riverpod, existing transaction widget tests.

---

## File Structure

### Modify

- `mobile/lib/features/main/presentation/main_shell_page.dart`: tune bottom sheet shape, clipping, elevation, and background.
- `mobile/lib/features/transactions/presentation/quick_transaction_page.dart`: add premium embedded header, amount surface, grouped form sections, and clearer save affordance.
- `mobile/test/main_shell_widget_test.dart`: preserve quick transaction reachability and verify the bottom sheet opens.
- `mobile/test/quick_transaction_form_validation_test.dart`: preserve validation/business behavior and add embedded premium form coverage.

## Task 1: Tune Main Shell Bottom Sheet

**Files:**
- Modify: `mobile/lib/features/main/presentation/main_shell_page.dart`
- Test: `mobile/test/main_shell_widget_test.dart`

- [x] **Step 1: Update bottom sheet presentation**

Use a transparent background, rounded top corners, drag handle support, and scroll control while still rendering `QuickTransactionPage(embedded: true)`.

- [x] **Step 2: Run shell focused test**

Run: `cd mobile && flutter test test/main_shell_widget_test.dart`

Expected: PASS.

## Task 2: Premium Quick Transaction Form

**Files:**
- Modify: `mobile/lib/features/transactions/presentation/quick_transaction_page.dart`
- Test: `mobile/test/quick_transaction_form_validation_test.dart`

- [x] **Step 1: Add embedded premium test coverage**

Verify embedded mode renders:

- `记一笔`
- `金额`
- `保存`
- at least one `PremiumSurface`

- [x] **Step 2: Refactor embedded shell**

Use `PremiumSurface`, safe keyboard padding, drag handle, and clear close affordance. Keep non-embedded route behavior compatible.

- [x] **Step 3: Refactor form hierarchy**

Group the amount/type controls separately from account/category/date/member/attachments. Keep all field keys and labels stable so existing tests and user muscle memory survive.

- [x] **Step 4: Run quick transaction focused tests**

Run: `cd mobile && flutter test test/quick_transaction_form_validation_test.dart`

Expected: PASS.

## Task 3: Final Verification

**Files:**
- All changed mobile files.

- [x] **Step 1: Run analyzer**

Run: `cd mobile && flutter analyze`

Expected: PASS.

- [x] **Step 2: Run mobile tests**

Run: `cd mobile && flutter test`

Expected: PASS.

- [x] **Step 3: Run whitespace check**

Run: `git diff --check`

Expected: PASS.

## Out Of Scope

- No backend changes.
- No Web/GSAP changes.
- No AI Reports redesign in this phase.
- No Family Hub redesign in this phase.
- No attachment behavior rewrites.
