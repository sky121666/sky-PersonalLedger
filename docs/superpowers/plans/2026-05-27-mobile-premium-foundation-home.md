# Mobile Premium Foundation Home Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first executable slice of the premium mobile direction by adding reusable Flutter motion/surface primitives and applying them to the Home dashboard.

**Architecture:** Keep this phase limited to the Flutter mobile app. Add shared widgets under `mobile/lib/app/widgets`, expand motion tokens under `mobile/lib/app/theme`, and refactor Home widgets to use those primitives without changing backend contracts or Web behavior.

**Tech Stack:** Flutter, Material 3, Riverpod, GoRouter, existing widget tests.

---

## File Structure

### Create

- `mobile/lib/app/widgets/premium_surface.dart`: reusable premium card/sheet surface with border, shadow, radius, tint, and optional press handling.
- `mobile/lib/app/widgets/pressable_scale.dart`: reusable touch feedback widget using scale and opacity.
- `mobile/lib/app/widgets/staggered_entrance.dart`: reusable list/dashboard entrance animation.
- `mobile/test/premium_motion_widgets_test.dart`: focused tests for reusable widgets.

### Modify

- `mobile/lib/app/theme/motion_tokens.dart`: expand the token contract.
- `mobile/lib/app/widgets/animated_money_text.dart`: improve amount animation duration, tabular figures, and reduced-motion behavior.
- `mobile/lib/features/home/presentation/home_page.dart`: apply staggered entrance and premium dashboard layout.
- `mobile/lib/features/home/presentation/widgets/home_dashboard_widgets.dart`: upgrade quick action and family summary cards.
- `mobile/test/animated_money_text_test.dart`: cover reduced-motion and stable formatting.
- `mobile/test/home_widget_test.dart`: preserve existing behavior expectations and add premium home surface expectations.

## Task 1: Expand Motion Tokens

**Files:**
- Modify: `mobile/lib/app/theme/motion_tokens.dart`

- [x] **Step 1: Add complete duration and curve tokens**

Add `instant`, `short`, `medium`, `long`, `emphasized`, `staggerStep`, `curveStandard`, `curveExit`, and `curveEmphasized`.

- [x] **Step 2: Run analyzer**

Run: `cd mobile && flutter analyze`

Expected: PASS.

## Task 2: Add Premium Motion Widgets

**Files:**
- Create: `mobile/lib/app/widgets/pressable_scale.dart`
- Create: `mobile/lib/app/widgets/premium_surface.dart`
- Create: `mobile/lib/app/widgets/staggered_entrance.dart`
- Test: `mobile/test/premium_motion_widgets_test.dart`

- [x] **Step 1: Add widget tests first**

Tests should verify:

- `PremiumSurface` renders its child and is tappable when `onTap` is provided.
- `PressableScale` renders its child and invokes `onTap`.
- `StaggeredEntrance` renders its child after settling.

- [x] **Step 2: Implement widgets**

Implement focused widgets with transform/opacity only. Avoid layout-shifting animations.

- [x] **Step 3: Run focused tests**

Run: `cd mobile && flutter test test/premium_motion_widgets_test.dart`

Expected: PASS.

## Task 3: Upgrade Animated Money Text

**Files:**
- Modify: `mobile/lib/app/widgets/animated_money_text.dart`
- Modify: `mobile/test/animated_money_text_test.dart`

- [x] **Step 1: Add reduced-motion coverage**

Test that `MediaQuery(disableAnimations: true)` still renders the final formatted amount.

- [x] **Step 2: Update implementation**

Use `MotionTokens.long` by default, preserve tabular figures, and collapse animation duration to zero when animations are disabled.

- [x] **Step 3: Run focused tests**

Run: `cd mobile && flutter test test/animated_money_text_test.dart`

Expected: PASS.

## Task 4: Upgrade Home Dashboard

**Files:**
- Modify: `mobile/lib/features/home/presentation/home_page.dart`
- Modify: `mobile/lib/features/home/presentation/widgets/home_dashboard_widgets.dart`
- Modify: `mobile/test/home_widget_test.dart`

- [x] **Step 1: Update home tests**

Keep existing assertions and add checks for:

- Premium quick action copy is still visible.
- Family summary remains visible with member data.
- Empty account state remains visible.

- [x] **Step 2: Refactor Home layout**

Use `StaggeredEntrance`, `PremiumSurface`, `PressableScale`, and stronger dashboard hierarchy for:

- Net assets card.
- Monthly overview.
- Quick action.
- Family summary.
- Account and budget previews.

- [x] **Step 3: Run focused home tests**

Run: `cd mobile && flutter test test/home_widget_test.dart`

Expected: PASS.

## Task 5: Final Verification

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

- No Quick Transaction redesign in this phase.
- No AI Reports redesign in this phase.
- No Family Hub page redesign in this phase.
- No Web GSAP work in this phase.
- No backend changes in this phase.
