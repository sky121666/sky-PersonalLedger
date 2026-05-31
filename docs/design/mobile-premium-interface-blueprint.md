# Mobile Premium Interface Blueprint

## Conclusion

The mobile redesign should start with the Flutter app and treat iOS and Android as one shared product experience with platform tuning, not as two separate redesigns. The correct workflow is:

1. Design every important interface first.
2. Split each interface into interaction behavior, visual components, data states, and validation criteria.
3. Implement in small batches, starting with the highest-visibility screens.

The P0 visual target is a quiet futuristic finance dashboard: premium, data-dense, native-feeling, and restrained. It should not become a decorative marketing UI.

## Current Gap

| Area | Current State | Design Gap |
| --- | --- | --- |
| Home | Functional dashboard with `PremiumSurface` cards | Still reads like stacked Material cards, not a finance control center |
| Statistics | Custom simple bars and rankings | Needs modern chart language, stronger hierarchy, better category visualization |
| Quick Transaction | Functional sheet/page flow | Needs faster premium entry, better picker layout, stronger save/validation feedback |
| Family | Functional summary, budget, ranking, members | Needs a first-class Family Hub identity and member visualization |
| AI Reports | Provider setup and report list exist | Needs insight-center structure instead of settings/list feeling |
| Secondary pages | Mostly default `Card`, `ListTile`, `CircleAvatar`, `IconButton` | Needs shared premium list, tile, sheet, dialog, and icon badge components |

## Interface Inventory

| Priority | Interface | Design Fidelity | Notes |
| --- | --- | --- | --- |
| P0 | Home dashboard | High-fidelity | First quality signal; defines product look |
| P0 | Statistics | High-fidelity | Core data visualization language |
| P0 | Quick transaction sheet/page | High-fidelity | Highest-frequency workflow |
| P1 | Transaction list/details | High-fidelity | Spending history, detail hierarchy, attachments |
| P1 | Accounts | High-fidelity | Financial account identity and balance cards |
| P1 | Budgets | High-fidelity | Ring/progress/risk visualization |
| P2 | Family Hub | High-fidelity | Member cards, contribution, member budgets |
| P2 | AI Insight Reports | High-fidelity | Weekly summary, risks, suggestions, provider state |
| P2 | Yearly report | High-fidelity | Annual narrative and chart system |
| P2 | Lending/reminders | Standard fidelity | Risk/time/payment state components |
| P3 | Categories/tags/templates | Standard fidelity | Management pages using shared list/editor components |
| P3 | Profile/settings/security/data/API tokens | Component fidelity | Needs polish, but not full custom layout per page |
| P3 | Login/setup/server config/bootstrap | Component fidelity | Trustworthy onboarding and setup states |
| P3 | Dialogs/bottom sheets/empty/loading/error | Component spec | One reusable system, not page-specific styling |

## Design Image Set

Design images should be produced in this order. Each design image must be followed by interaction notes and component extraction before coding.

| Batch | Image | Screens Included | Purpose |
| --- | --- | --- | --- |
| D0 | Visual direction board | Home, Statistics, Quick Entry, Family, AI | Align taste and product language |
| D1 | Home dashboard | Empty, normal, dense/family data, dark mode | Define first-screen information hierarchy |
| D2 | Statistics analytics | Overview, category ranking, trend, dark mode | Define chart language |
| D3 | Quick transaction | Add, edit, validation, keyboard, success | Define high-frequency flow |
| D4 | Accounts + transactions | Account cards, transaction list, detail | Define daily browsing/editing language |
| D5 | Budget + family | Budget dashboard, Family Hub, member detail | Define household visualization |
| D6 | AI + yearly report | AI weekly insight, annual report | Define insight/narrative reporting |
| D7 | System pages | Settings, security, backup, API tokens, setup | Apply shared components consistently |

## Visual System

| Token | Direction |
| --- | --- |
| Style | Quiet futuristic finance OS |
| Light mode | Warm off-white/neutral canvas, graphite text, subtle teal/cyan/amber accents |
| Dark mode | Graphite/near-black surfaces, low-contrast borders, teal highlights, restrained glow only on data accents |
| Primary | Deep teal for brand/action |
| Semantic | Green income, red expense/risk, amber warning, blue asset/data |
| Radius | 12 controls, 16 compact cards, 20-24 dashboard surfaces, 28 bottom sheets |
| Shadows | Soft elevation and border layering; avoid heavy floating card stacks |
| Typography | Strong tabular finance numbers, compact labels, fewer explanatory sentences |
| Icons | Shared icon badge system; avoid emoji as primary UI icons |
| Charts | Rounded bars, rings, sparklines, progress tracks, percentage bars, accessible legends |

## Theme Templates

The app should support multiple premium color templates from Settings. Templates change the product accent and generated Material color scheme, while income/expense semantics remain stable for financial clarity.

| Template | Intent | Seed |
| --- | --- | --- |
| Quiet Teal | Default private finance style | `#0F766E` |
| Graphite Blue | Colder, dashboard-like, more executive | `#334155` |
| Deep Indigo | More technical, suitable for AI insight emphasis | `#4338CA` |
| Emerald | Lighter daily ledger feeling | `#047857` |
| Amber Gold | Warmer premium tone without bright gold overload | `#B45309` |

Settings should expose:

- Appearance mode: system, light, dark.
- Theme template: the five palettes above, with color previews.
- Local persistence through device preferences.

Semantic finance colors should not become arbitrary theme colors:

- Income stays green.
- Expense/risk stays red.
- Warning stays amber.
- Asset/data accents may follow the selected template after shared components are introduced.

## Core Components To Build

| Component | Purpose | Used By |
| --- | --- | --- |
| `FinanceScaffold` | Shared page background, safe area, title/action rhythm | All premium pages |
| `PremiumAppBarTitle` | Compact title, period/status subtitle, refresh state | Home, Statistics, Family, AI |
| `FinanceHeroCard` | Large money/value hero with sparkline and secondary metrics | Home, Family, Accounts |
| `MetricPill` | Small income/expense/balance/status data block | Home, Statistics, Budgets |
| `IconBadge` | Consistent category/account/member/provider icon language | Most pages |
| `MiniTrendChart` | Sparkline and compact cashflow chart | Home, Accounts, AI |
| `RoundedBarChart` | Trend and comparison bars | Statistics, Yearly report |
| `ProgressRing` | Budget and completion visualization | Home, Budgets |
| `CategoryRankTile` | Icon, label, amount, percent, progress | Statistics, Reports |
| `FamilyMemberCard` | Member identity, spending, budget, default/enabled state | Family, Home |
| `InsightCard` | AI/budget/risk/recommendation cards | AI, Home, Reports |
| `PremiumBottomSheet` | Drag handle, keyboard-safe layout, sticky actions | Quick entry, filters, editors |
| `PremiumListTile` | Replacement for default `ListTile` in dense pages | Settings, management pages |
| `PremiumStateView` | Loading, empty, error, success | All pages |

## Interaction System

| Interaction | Behavior |
| --- | --- |
| Page entry | Existing platform transitions stay stable; premium pages use in-page stagger only on first content load |
| Pull refresh | Do not blank the page if old data exists; refresh affected cards with local progress |
| Card tap | Press scale 0.98, short state layer, optional light haptic on primary actions |
| Number update | Animate finance values with tabular figures; no layout shift |
| Chart update | Grow bars/rings and crossfade labels; duration 300-450ms |
| Quick entry open | Bottom sheet from bottom, keyboard-safe, amount focused when creating |
| Quick entry save | Disable button, inline loading, haptic on success, close sheet, refresh affected views |
| AI generation | Progressive skeleton, status timeline, failed state with retry |
| Family member edit | Preserve list context; avoid full page jump when editing a member |
| Reduced motion | Replace translation/scale with short fade or static update |

## Screen-Level Design Notes

### Home Dashboard

- Replace generic title text with current period, refresh status, and privacy-safe overview.
- Net assets becomes a hero surface with animated amount, sparkline, total assets/liabilities, and month delta.
- Income, expense, balance, budget, family, and AI become compact data modules instead of plain text rows.
- Quick action should feel docked and reachable, not buried in a card.

### Statistics

- Use a period selector and segmented dimensions: overview, category, member, account.
- Replace basic bar pairs with rounded, animated chart blocks.
- Category ranking should show icon badge, amount, percent, and progress track.
- Charts must include text summaries for accessibility.

### Quick Transaction

- Keep the workflow fast: amount first, type segmented, then account/category/member/date.
- Pickers should be compact surfaces with clear icons and values.
- Save action stays sticky and keyboard-safe.
- Validation appears near fields, not only as toast/snackbar.

### Family Hub

- Treat family as a dashboard, not just a member list.
- Header shows total family spending, active members, and budget state.
- Member cards show avatar/color, relationship, monthly spending, contribution, and enabled/default state.
- Member budget and ranking should share the same progress language as Statistics/Budgets.

### AI Insight

- AI should read as an insight center.
- Provider setup must be visible but subordinate once configured.
- Report cards show period, model/provider status, summary, risks, suggestions, and action.
- Never display raw keys or secret values.

### Secondary Management Pages

- Do not make high-fidelity bespoke layouts for every settings page.
- Use `PremiumListTile`, `IconBadge`, `PremiumBottomSheet`, and consistent form sections.
- Keep density high, but replace plain `Card/ListTile` stacks with structured sections.

## Implementation Sequence

| Batch | Scope | Files |
| --- | --- | --- |
| B0 | Design foundation docs and visual direction | `docs/design/*` |
| B1 | Design tokens and shared components | `mobile/lib/app/theme`, `mobile/lib/app/widgets` |
| B2 | Home dashboard implementation | `home_page.dart`, `home_dashboard_widgets.dart` |
| B3 | Statistics implementation | `mobile_statistics_page.dart` |
| B4 | Quick transaction implementation | `quick_transaction_page.dart`, main shell sheet trigger |
| B5 | Accounts/transactions/budgets | Feature pages and shared tiles |
| B6 | Family/AI/yearly report | Feature pages and insight components |
| B7 | Secondary pages and system states | Settings, security, data, tags, templates |
| B8 | iOS/Android tuning and evidence | Simulator/device tests and screenshots |

## Verification Standard

Each implementation batch must pass:

- `flutter analyze`
- Targeted widget/integration tests for changed screens
- `flutter test test/premium_accessibility_test.dart`
- iOS Simulator visual smoke for key screens
- Android device or emulator smoke when mobile layout changes are substantial
- Manual review for overflow, text clipping, safe areas, bottom navigation, and keyboard coverage

## Stop Rules

- Do not change business logic while doing pure visual refactors unless a UI bug makes it necessary.
- Do not redesign all pages in one commit.
- Do not introduce GSAP into Flutter mobile.
- Do not add heavy chart or animation libraries until custom lightweight widgets are proven insufficient.
- Do not claim final release quality without signed artifacts and real device evidence.
