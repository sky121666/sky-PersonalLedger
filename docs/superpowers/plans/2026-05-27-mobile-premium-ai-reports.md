# Mobile Premium AI Reports Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade the mobile AI reports screen into a premium insight layer with clear empty, generating, failed, and completed states while preserving the existing OpenAI-compatible report API contract.

**Architecture:** Keep this phase limited to Flutter presentation. Reuse the premium motion primitives from the Foundation phase and do not change backend, Web, provider storage, or report generation business rules.

**Tech Stack:** Flutter, Material 3, Riverpod, existing AI report repository and widget tests.

---

## File Structure

### Modify

- `mobile/lib/features/ai/presentation/ai_reports_page.dart`: premium AI report state layout, report cards, status chips, generation feedback, and structured content sections.
- `mobile/test/ai_reports_widget_test.dart`: preserve existing behavior and add premium state coverage.

## Task 1: Premium AI Report State Coverage

**Files:**
- Modify: `mobile/test/ai_reports_widget_test.dart`

- [x] **Step 1: Preserve existing behavior tests**

Keep coverage for list rendering, empty state, and weekly report generation.

- [x] **Step 2: Add premium report content expectations**

Verify completed report cards render:

- `PremiumSurface`
- provider/model metadata
- summary
- highlights
- risks
- suggestions

- [x] **Step 3: Add failed report expectations**

Verify failed reports show the failed status and error message inline without exposing secrets.

## Task 2: Premium AI Report UI

**Files:**
- Modify: `mobile/lib/features/ai/presentation/ai_reports_page.dart`

- [x] **Step 1: Replace generic list cards**

Use `PremiumSurface` and `StaggeredEntrance` for report list items. Keep report expansion and existing labels stable.

- [x] **Step 2: Improve empty and generating states**

Show a premium empty state with a generate action, and show an inline generating surface while report generation is in progress.

- [x] **Step 3: Render structured report sections**

Parse `summary`, `highlights`, `risks`, and `suggestions` from `content_json` and render them with clear hierarchy.

- [x] **Step 4: Preserve API and privacy boundaries**

Do not display raw API keys. Only display provider name and model from report metadata.

## Task 3: Verification

**Files:**
- All changed mobile AI report files.

- [x] **Step 1: Run focused test**

Run: `cd mobile && flutter test test/ai_reports_widget_test.dart`

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
- No provider management UI in mobile in this phase.
- No scheduling automation for weekly reports in this phase.
- No raw AI provider secret display.
