# Mobile Premium Family Hub Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade the mobile Family Hub into a premium lightweight family accounting screen with member identity, monthly spending context, ranking, and clear enabled/default/disabled states.

**Architecture:** Keep this phase limited to Flutter mobile. Use the existing backend `/family/members` and `/family/summary` contracts. Reuse premium motion primitives and do not change backend or Web behavior.

**Tech Stack:** Flutter, Material 3, Riverpod, existing family repository and widget tests.

---

## File Structure

### Modify

- `mobile/lib/features/family/data/family_repository.dart`: add family summary API model and provider.
- `mobile/lib/features/family/presentation/family_page.dart`: premium family hub layout, summary cards, member ranking, and richer member cards.
- `mobile/test/family_widget_test.dart`: preserve list/empty tests and add summary/ranking/premium state coverage.

## Task 1: Family Summary Repository

**Files:**
- Modify: `mobile/lib/features/family/data/family_repository.dart`
- Test: `mobile/test/family_widget_test.dart`

- [x] **Step 1: Add summary models**

Add `FamilySummary` and `FamilyMemberSummary` matching backend JSON fields.

- [x] **Step 2: Add summary provider**

Add `familySummaryProvider` that calls `GET /family/summary`.

## Task 2: Premium Family Hub UI

**Files:**
- Modify: `mobile/lib/features/family/presentation/family_page.dart`

- [x] **Step 1: Replace generic member list cards**

Use `PremiumSurface` and `StaggeredEntrance` for members.

- [x] **Step 2: Add family summary surfaces**

Show enabled member count, current month, total expense, and spending ranking/proportion when summary data exists.

- [x] **Step 3: Improve member identity states**

Show member initial, relationship, default state, enabled/disabled state, and color as accent instead of full-card fill.

- [x] **Step 4: Improve empty state**

Use a premium empty state that makes the add-member path visible as a reserved next action.

## Task 3: Verification

**Files:**
- All changed mobile family files.

- [x] **Step 1: Run focused test**

Run: `cd mobile && flutter test test/family_widget_test.dart`

Expected: PASS.

- [x] **Step 2: Run analyzer**

Run: `cd mobile && flutter analyze`

Expected: PASS.

- [x] **Step 3: Run mobile tests**

Run: `cd mobile && flutter test`

Expected: PASS.

- [x] **Step 4: Run whitespace check**

Run: `git diff --check`

Expected: PASS.

## Out Of Scope

- No backend changes.
- No Web/GSAP changes.
- No full create/edit form in this phase.
- No destructive member delete behavior changes.
- No multi-user or multi-tenant behavior.
