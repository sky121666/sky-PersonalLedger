# Mobile Modernization

## Decision

The Web UI is acceptable for the current product direction. The main experience gap is the Flutter mobile app. The mobile app should evolve toward a modern native finance app: high trust, high clarity, polished motion, strong data hierarchy, and platform-respectful interactions on iOS and Android.

The goal is not decorative animation. Motion must communicate state changes, reinforce hierarchy, and make frequent actions feel fast.

## Design Principles

| Principle | Rule |
| --- | --- |
| Finance first | Amounts, balances, budget progress, and risk signals are primary content |
| Calm premium | Use restrained surfaces, low-saturation accents, and precise spacing |
| Native behavior | Respect safe areas, platform back gestures, bottom sheets, and touch targets |
| Meaningful motion | Animate amount changes, sheet transitions, tab switches, and chart changes |
| Fast entry | Quick transaction must stay low-friction |
| Family-ready | Member context should be visible but not noisy |
| Accessible | Maintain contrast, Dynamic Type resilience, and 44px+ touch targets |

## Visual Direction

Working name: Modern Native Finance.

| Token | Direction |
| --- | --- |
| Primary | Deep green or graphite blue, not neon |
| Accent | Muted gold or cyan for highlights only |
| Surfaces | Layered neutral surfaces with subtle borders |
| Radius | 12-20px on mobile cards and sheets, consistent by component class |
| Shadows | Soft elevation for sheets and floating actions; avoid heavy card shadows |
| Numbers | Tabular figures for balances, totals, and percentages |
| Charts | Smooth line, ring, and stacked bars with accessible legends |
| Icons | Keep a single icon language; avoid emoji as primary UI icons |

## Motion System

| Motion | Duration | Curve | Use |
| --- | ---: | --- | --- |
| Tap feedback | 80-120ms | easeOut | Buttons, cards |
| Sheet entrance | 220-300ms | emphasized easeOut or spring | Quick transaction, filters |
| Page transition | 220-320ms | platform default or easeOut | Secondary pages |
| Number change | 350-500ms | easeOutCubic | Balance and spending deltas |
| Chart update | 300-450ms | easeInOut | Month/member/category changes |
| List insert/delete | 180-260ms | easeOut | Transaction list updates |

Animations must be interruptible. Avoid animating width, height, top, or left when transform/opacity can express the same state.

## Target Screens

### 1. Home Dashboard

Current home should become a mobile financial dashboard:

- Current period selector.
- Primary balance or monthly net cashflow.
- Income, expense, and remaining budget summary.
- Cashflow mini chart.
- Family member spending strip when family mode is enabled.
- Risk cards: over-budget, repayment due, unusual spending.
- Quick transaction floating action.

### 2. Quick Transaction

The first premium interaction should be quick transaction:

- Trigger from floating action.
- Open as a bottom sheet on mobile.
- Amount field gets immediate focus.
- Type selector uses segmented control.
- Category/member/account fields use compact pickers.
- Save button shows loading state.
- Success animates sheet close and inserts transaction into home/list.

### 3. Statistics

Statistics should feel analytical, not just informational:

- Segmented control: Overview / Category / Member / Account.
- Month swipe navigation.
- Animated chart transitions.
- Member dimension once family mode exists.
- Empty and loading states should reserve stable space.

### 4. Family Hub

Family Hub should be a first-class mobile section after family mode exists:

- Member cards.
- Monthly family spending.
- Member ranking.
- Family budget progress.
- Quick member edit.

## Flutter Implementation Direction

| Need | Flutter approach |
| --- | --- |
| Shared design tokens | Extend `app/theme/app_theme.dart` with motion, radii, spacing, semantic colors |
| Dashboard cards | Small focused widgets under `mobile/lib/features/home/presentation/` |
| Number animation | `TweenAnimationBuilder` or custom animated number widget |
| Bottom sheets | `showModalBottomSheet` with safe area, drag handle, controlled height |
| Chart animation | Start with lightweight custom painters or existing simple widgets; avoid heavy libraries until needed |
| Haptics | Use `HapticFeedback.lightImpact()` for success and important selections |
| Accessibility | Add semantic labels for icon buttons and chart summaries |

## Acceptance Criteria

- No horizontal overflow at common mobile widths.
- Main touch targets are at least 44 logical pixels.
- Quick transaction can be completed with fewer taps than the current full-page flow.
- Motion does not block input and does not cause layout jumps.
- Home remains usable with zero data, partial data, and dense data.
- iOS simulator and Android emulator screenshots are captured for Home and Quick Transaction.
- `flutter analyze`, `flutter test`, and real backend Flutter tester E2E pass.

## Non-Goals

- Rebuilding the Web UI.
- Separate native SwiftUI and Kotlin clients.
- Decorative 3D scenes.
- Large animated backgrounds.
- Platform-specific divergent business flows.

