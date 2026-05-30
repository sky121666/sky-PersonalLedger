# Mobile Premium Motion System

## Conclusion

Personal Ledger should upgrade the mobile app toward a quiet futuristic finance experience. The first target is not visual decoration. The target is a system-level mobile interaction language that makes the private ledger feel precise, fast, native, and high-end on both iOS and Android.

This design is for the Flutter mobile app. GSAP is not part of the mobile implementation path. GSAP can be considered later for the Vue Web app only.

## Current Baseline

| Area | Current State | Gap |
| --- | --- | --- |
| Motion tokens | `MotionTokens.short`, `medium`, `long`, `enter`, `exit`, `emphasized` exist | Too small for a full interaction system |
| Amount animation | `AnimatedMoneyText` exists | Needs stronger number stability, delta feedback, and reduced-motion behavior |
| Home | Functional dashboard with net assets, monthly overview, quick action, family summary, accounts, budget | Still feels like standard Material cards rather than a premium finance surface |
| Quick transaction | Supports embedded bottom sheet and member selector | Needs a dedicated high-frequency flow with stronger sheet motion, focus, picker ergonomics, and success feedback |
| AI reports | Functional list, generation action, expandable report content | Needs premium empty/loading/generation states and structured report cards |
| Family | Functional page and home summary | Needs member identity, spending hierarchy, and richer card interactions |

## Product Experience Target

Working style name: **Quiet Futuristic Finance OS**.

| Principle | Rule |
| --- | --- |
| Finance first | Money, cash flow, budget risk, and member spending are always more important than decoration |
| Premium restraint | Use surface depth, typography, spacing, and motion instead of loud gradients or animated backgrounds |
| Native fluidity | iOS should feel soft and spatial; Android should feel clear, responsive, and stateful |
| High-frequency speed | Quick transaction must become faster, not heavier |
| Motion with purpose | Every animation must explain hierarchy, continuity, state change, or user feedback |
| Private by default | AI and family visuals must not expose sensitive detail unnecessarily |
| Performance before spectacle | No large continuous background animations, no expensive full-screen blur loops, no decorative particles |

## Platform Position

| Platform | Primary Technology | Motion Guidance |
| --- | --- | --- |
| iOS app | Flutter running on iOS | Safe-area aware sheets, fluid page transitions, soft surface depth, light haptics |
| Android app | Flutter running on Android | Material state layers, clear press feedback, predictable back behavior, stable layout |
| Web app | Vue | GSAP may be used later for Web-only route/card/chart animations |

Do not introduce GSAP into Flutter. Flutter mobile motion should use `AnimationController`, `TweenAnimationBuilder`, implicit animated widgets, `CustomTransitionPage` or route builders, `DraggableScrollableSheet`, `HapticFeedback`, and focused custom widgets.

## Visual System

| Token Group | Direction |
| --- | --- |
| Color | Graphite, deep green, muted cyan, neutral surfaces, finance semantic green/red |
| Surface | Layered cards with subtle border, low-opacity tint, controlled shadow, optional local blur only for modal backdrops |
| Radius | 12 for controls, 16 for compact cards, 20-24 for dashboard cards, 28 for modal sheets |
| Typography | Strong amount hierarchy, tabular figures, compact labels, no negative letter spacing |
| Icons | Platform-consistent Material icons for mobile; avoid emoji as primary interface icons |
| Spacing | 4/8-point rhythm; dashboard sections use stable vertical rhythm |
| Dark mode | First-class design, not inverted light mode |

## Motion Tokens

The current `MotionTokens` should evolve from three durations into a complete contract.

| Token | Value Direction | Use |
| --- | --- | --- |
| `instant` | 80-100ms | Tap down, minor state flash |
| `short` | 140-180ms | Button release, chip select, icon change |
| `medium` | 220-280ms | Card state, picker reveal, list item entrance |
| `long` | 320-420ms | Page transition, sheet entrance, chart transition |
| `emphasized` | 420-560ms | Success confirmation, primary dashboard amount reveal |
| `curveStandard` | easeOutCubic | Most enter/update states |
| `curveExit` | easeInCubic | Dismiss and reverse states |
| `curveEmphasized` | fastOutSlowIn or spring-like cubic | Sheet/page hierarchy motion |
| `staggerStep` | 32-48ms | Dashboard card and report section entrance |

Reduced motion must replace translation/scale with short fade or no animation for non-critical movement.

## Core Components To Build First

| Component | Purpose | Notes |
| --- | --- | --- |
| `PremiumSurface` | Shared high-end card/sheet surface | Handles radius, border, shadow, dark mode, press state |
| `PressableScale` | Consistent touch feedback | Scale 0.97-0.99, opacity or state layer, haptic optional |
| `StaggeredEntrance` | Controlled dashboard/list entry | No layout shift, opacity + y transform only |
| `PremiumAmountText` | Stable animated finance number | Tabular figures, optional delta color, reduced-motion path |
| `PremiumBottomSheet` | Quick transaction and pickers | Drag handle, safe area, keyboard padding, backdrop, clear close affordance |
| `MetricPill` | Compact finance metric | Income/expense/budget/risk labels |
| `InsightCard` | AI/family/budget insight | Shared visual language for recommendations and alerts |

Build these before redesigning pages. Page-level work without these components will create inconsistent motion.

## Screen Design

### Phase 1: Home Dashboard

Home is the first quality signal. It should feel like a personal finance operating surface.

Required layout:

1. Header with current month and subtle refresh state.
2. Premium net assets card with animated amount and compact total assets/liabilities.
3. Monthly cashflow strip: income, expense, balance.
4. Insight row: quick transaction, family spending, AI report, budget state.
5. Account preview and recent transaction preview.

Motion:

- Dashboard sections enter with a short stagger on first load.
- Amounts animate only when values change.
- Refresh uses local skeleton or shimmer inside affected cards instead of replacing the whole screen when data already exists.
- Cards use press scale and clear route transition.

Acceptance:

- Empty data still looks intentional.
- Dense data does not overflow.
- Refresh does not cause whole-page layout jump.
- Home widget tests cover empty, normal, and family-summary states.

### Phase 2: Quick Transaction

Quick transaction is the most important workflow. It should be optimized before secondary visual polish.

Required flow:

1. Main shell action opens a premium bottom sheet.
2. Amount field receives immediate focus when appropriate.
3. Transaction type uses a segmented control.
4. Category, account, member, tags, and date are compact pickers.
5. Save button has loading state and disabled-state clarity.
6. Success gives haptic feedback, closes sheet, and refreshes home/list.

Motion:

- Sheet enters from bottom with emphasized curve.
- Pickers reveal through fade + slight y motion.
- Save success uses short scale/fade confirmation, not a long celebration.
- Keyboard appearance must not cover save action.

Acceptance:

- A simple expense can be entered quickly.
- Validation errors stay near fields.
- Member selector is visible only when family members exist.
- Existing attachment behavior remains intact.

### Phase 3: AI Reports

AI should feel like a premium insight layer, not a settings appendix.

Required layout:

1. Empty state explains that provider setup is required without exposing secrets.
2. Generate button clearly indicates disabled, generating, success, and failure states.
3. Report cards show period, type, status, provider/model, summary.
4. Expanded report sections render summary, highlights, risks, and suggestions with hierarchy.

Motion:

- Report generation uses progressive skeleton sections.
- Expanding content uses vertical size transition only if it stays smooth; otherwise use fade/crossfade.
- New report insertion is highlighted once.

Acceptance:

- Provider missing state is understandable.
- Failed report state is visible and recoverable.
- Raw AI keys are never displayed.

### Phase 4: Family Hub

Family mode should stay lightweight and personal.

Required layout:

1. Member cards with name, relationship, color/avatar, enabled/default state.
2. Monthly family spending total.
3. Member ranking and proportion indicators.
4. Add/edit member flow with clear validation.
5. Home family card links into the hub.

Motion:

- Member cards use press feedback.
- Ranking changes animate position only if stable and cheap; otherwise use fade/crossfade.
- Editing a member should preserve context and avoid full-page jumps.

Acceptance:

- Historical disabled members remain understandable.
- Empty state leads to adding a member.
- Member color is used as accent, not full-card fill.

## Task Sequencing

Do not implement all screens at once. The correct order is:

| Order | Task | Why |
| ---: | --- | --- |
| 1 | Foundation components and tokens | Prevents inconsistent page-specific animation |
| 2 | Home dashboard | Highest visibility and easiest to validate style direction |
| 3 | Quick transaction | Highest usage frequency; proves the motion system helps real work |
| 4 | AI reports | New premium feature, lower risk after foundation exists |
| 5 | Family hub | New feature polish after member data path is stable |
| 6 | Platform QA and tuning | Final pass for iOS/Android differences, performance, accessibility |
| 7 | Optional Web GSAP layer | Separate from mobile; only after mobile direction is stable |

## Suggested Agent Roles

| Agent | Responsibility | Inputs | Output |
| --- | --- | --- | --- |
| Design Director | Own visual language, component quality, screen hierarchy | This spec, current Flutter UI | Component and screen review decisions |
| Flutter Motion Architect | Build tokens/components and prevent one-off animation code | `mobile/lib/app/theme`, `mobile/lib/app/widgets` | Reusable motion/surface widgets |
| Home Experience Engineer | Upgrade home dashboard using foundation components | Home repository and widgets | Premium home implementation |
| Quick Entry Engineer | Optimize quick transaction bottom sheet and pickers | Transaction/family/attachment flows | Faster premium entry flow |
| AI Insight Engineer | Polish AI report generation and report rendering | AI report repository/page | Premium AI insight screen |
| Family Experience Engineer | Polish family hub and member identity states | Family repository/page | Premium family management screen |
| Mobile QA Engineer | Verify performance, overflow, tests, and platform behavior | iOS/Android simulator, Flutter tests | Evidence report and fixes |
| Web Motion Engineer | Optional GSAP work for Vue Web only | Web views | Web-specific motion layer |

## GSAP Boundary

| Use Case | GSAP? | Reason |
| --- | --- | --- |
| Flutter iOS/Android screens | No | Flutter native animation is more stable and native-feeling |
| Flutter route transitions | No | Use Flutter router/page transitions |
| Flutter charts/cards/sheets | No | Use Flutter animation widgets/controllers |
| Vue Web dashboard card entrance | Yes, optional | GSAP fits DOM animation |
| Vue Web statistics chart transitions | Conditional | Use GSAP only when the chart is DOM/SVG-based and the transition cannot be expressed cleanly with the chart library itself |
| Vue Web AI report reveal | Yes, optional | Good fit for timeline/stagger animation |

## Verification Plan

Each implementation phase must end with verification appropriate to its risk.

| Phase | Required Checks |
| --- | --- |
| Foundation | `flutter analyze`, focused widget tests for reusable widgets |
| Home | Home widget tests, small-screen overflow check, iOS/Android screenshots |
| Quick transaction | Existing quick transaction tests, real backend E2E, keyboard/sheet manual check |
| AI reports | AI report widget tests, provider-missing and failed-report states |
| Family hub | Family widget tests, empty/member/disabled states |
| Final mobile QA | `flutter analyze`, `flutter test`, real backend E2E, iOS simulator, Android emulator |

## Non-Goals

- Do not rewrite the backend for UI polish.
- Do not introduce GSAP to Flutter.
- Do not add decorative 3D, particles, or constantly moving backgrounds.
- Do not make iOS and Android divergent products.
- Do not sacrifice quick transaction speed for visual novelty.
- Do not redesign the entire Web app before mobile quality is proven.

## First Implementation Plan To Write Next

The next plan should be limited to **Foundation + Home Dashboard**.

Suggested plan file:

`docs/superpowers/plans/YYYY-MM-DD-mobile-premium-foundation-home.md`

Scope:

1. Expand `MotionTokens`.
2. Add `PremiumSurface`.
3. Add `PressableScale`.
4. Add `StaggeredEntrance`.
5. Upgrade `AnimatedMoneyText` or introduce `PremiumAmountText`.
6. Refactor Home dashboard to use the new components.
7. Add/update focused widget tests.
8. Run `flutter analyze` and `flutter test`.

This is the correct first batch because it proves the visual language on the highest-value screen without destabilizing quick transaction, AI, or family flows.
