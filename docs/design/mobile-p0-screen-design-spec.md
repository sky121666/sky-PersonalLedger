# Mobile P0 Screen Design Spec

## Conclusion

P0 should redesign three mobile experiences first: Home, Statistics, and Quick Transaction. These screens define the finance dashboard language, data visualization language, and high-frequency input language. If these three become premium and coherent, the rest of the app can follow with lower risk.

## P0 Visual Concept

Generated direction board:

`/Users/sky/.codex/generated_images/019e66ee-8527-7cb1-97fc-348dfa7377fe/ig_0593188d093b61fe016a1bb575b5448197be819ef9e7c61b73.png`

This image is a direction board, not a final implementation asset. The implementation source of truth remains Flutter components and screen specs below.

## 1. Home Dashboard

### Design Goal

Home should feel like a private finance control center, not a list of cards.

### First Screen Structure

| Zone | Content | Visual Treatment |
| --- | --- | --- |
| Header | Current month, privacy-safe status, refresh action | Compact title and subtitle; no instructional copy |
| Hero | Net assets, month delta, total assets, total liabilities | Large `FinanceHeroCard`, tabular amount, mini sparkline |
| Cashflow | Income, expense, balance | Three `MetricPill` blocks with semantic color and icons |
| Budget | Used/remaining/daily available | `ProgressRing` plus compact labels |
| Family/AI | Family spending and latest AI insight status | Horizontal insight strip with `InsightCard` |
| Accounts | Top accounts by balance or risk | `PremiumListTile` rows with `IconBadge` |

### Interactions

| Interaction | Behavior |
| --- | --- |
| Pull refresh | Keep existing content visible; show local refresh state in header/cards |
| Tap hero | Navigate to account overview or statistics |
| Tap cashflow | Navigate to statistics with selected dimension |
| Tap budget | Navigate to budget page |
| Tap family | Navigate to Family Hub |
| Tap AI insight | Navigate to AI reports |
| Quick action | Opens premium quick transaction sheet |

### Components Needed

- `FinanceHeroCard`
- `MetricPill`
- `ProgressRing`
- `MiniTrendChart`
- `InsightCard`
- `PremiumListTile`
- `IconBadge`

### Acceptance

- Empty data still looks deliberate.
- Dense account data does not overflow.
- Amount changes are stable and use tabular figures.
- The first screen explains financial state without extra help text.

## 2. Statistics

### Design Goal

Statistics should feel analytical and modern, with accessible charts rather than simple colored bars.

### First Screen Structure

| Zone | Content | Visual Treatment |
| --- | --- | --- |
| Header | Month selector and refresh | Compact title, chevron controls, disabled future month |
| Overview | Expense, income, balance, daily average | `FinanceHeroCard` or large analytic summary |
| Trend | Income/expense trend | `RoundedBarChart` with soft grouped bars and legend |
| Category rank | Category icon, name, amount, percent | `CategoryRankTile` with progress track |
| Dimension switch | Expense/income/member/account | Segmented control or compact tabs |

### Interactions

| Interaction | Behavior |
| --- | --- |
| Month switch | Chart crossfades/grows with stable layout |
| Segment switch | Ranking list crossfades; no full page reload feel |
| Category tap | Opens filtered transaction list or category detail |
| Pull refresh | Keeps chart frame height stable |

### Components Needed

- `RoundedBarChart`
- `CategoryRankTile`
- `MetricPill`
- `IconBadge`
- `PremiumSegmentedControl`
- `PremiumStateView`

### Acceptance

- Chart values are understandable without relying only on color.
- Ranking rows align amounts and percentages cleanly.
- Horizontal scrolling is only used when needed and does not hide key summaries.
- Light and dark modes both preserve contrast.

## 3. Quick Transaction

### Design Goal

Quick Transaction should be the fastest and most polished flow in the app.

### Sheet Structure

| Zone | Content | Visual Treatment |
| --- | --- | --- |
| Handle/header | Drag handle, title, close | `PremiumBottomSheet` safe-area header |
| Amount | Large amount input | Big tabular amount, clear currency prefix |
| Type | Expense/income/transfer | Segmented control with semantic icons |
| Essentials | Account, category/to-account, member, date | Compact picker tiles with `IconBadge` |
| Optional | Tags, remark, attachments | Progressive disclosure or lower section |
| Action | Save button | Sticky bottom action, loading state, disabled state |

### Interactions

| Interaction | Behavior |
| --- | --- |
| Open | Sheet slides up with emphasized curve; amount focuses for new transaction |
| Type switch | Category/to-account field morphs without layout jump |
| Picker tap | Opens compact picker sheet; preserves context |
| Validation | Error appears near field |
| Save | Button disables, spinner appears, success haptic, sheet closes, home/list refreshes |
| Keyboard | Save action remains visible and reachable |

### Components Needed

- `PremiumBottomSheet`
- `AmountInputPanel`
- `PremiumPickerTile`
- `PremiumSegmentedControl`
- `StickySheetActionBar`
- `ValidationMessage`

### Acceptance

- A simple expense remains fast to enter.
- Existing attachment behavior is preserved.
- Family member selector appears only when members exist.
- Keyboard does not cover the save action.

## Implementation Cut

| Step | Scope | Expected Change |
| --- | --- | --- |
| 1 | Add shared tokens/components | No page behavior change yet |
| 2 | Rebuild Home with new components | First visible premium result |
| 3 | Rebuild Statistics chart/rank sections | Data visualization upgrade |
| 4 | Rebuild Quick Transaction sheet internals | High-frequency workflow polish |
| 5 | Run simulator/device visual smoke | Verify real screen behavior |

## Test Plan

| Command | Purpose |
| --- | --- |
| `flutter analyze` | Static correctness |
| `flutter test test/premium_accessibility_test.dart` | Semantics and tap targets |
| `flutter test test/quick_transaction_form_validation_test.dart` | Quick entry behavior |
| `flutter test -d C417531C-3ABC-4357-880C-4ECC9A1752D1 integration_test/premium_screens_smoke_test.dart` | iOS Simulator visual smoke |
| Android real backend E2E on `8413dfa50722` | Android physical-device functional confidence |

## Deferred

- Full Web redesign.
- New chart library adoption.
- Release screenshots and marketing images.
- iOS true device E2E until provisioning profile is available.
