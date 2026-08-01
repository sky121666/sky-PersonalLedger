# Mobile UI Redesign 95 Goal

## Conclusion

The mobile app should be redesigned around a quiet finance-control interface: fewer prompts, fewer duplicate entries, stronger money hierarchy, and restrained decoration. The target is not minimal emptiness; it is a dense, premium ledger that only shows information a user can act on.

Current completion is about 88/100. The path to 95+ is to remove structural UI pollution first, then unify page rhythm, then verify on Android and iOS simulators with real seeded data.

## Product Style

- Style: quiet premium finance OS.
- Density: compact enough for daily use, but with clear money hierarchy.
- Decoration: soft surface tint, one accent per block, no theme-market feeling.
- Navigation: four top-level tabs plus one right-side `+` for quick entry.
- Copy: no instructional or self-describing UI text unless it is an empty/error state.
- Motion: 120 Hz friendly, transform/opacity only for micro feedback, no expensive decorative effects.

## Page Audit

| Page | Current Score | Main Gap | Target |
| --- | ---: | --- | --- |
| Home | 88 | Duplicate quick action rail competes with right-side `+`; cashflow is clear but still card-stacked | 95 |
| Transactions | 90 | Needs stronger list density, filter state, and edit affordance | 95 |
| Statistics | 91 | Period data works; chart/rank density and hierarchy still need polish | 95 |
| Feature/Profile | 86 | Too many large setting tiles; theme selector felt like a color showroom | 95 |
| Quick Transaction | 88 | Fast path exists; amount-first and sticky action still need more native-feeling polish | 96 |
| Lending | 84 | Summary works, but record cards and dialogs feel like forms wrapped in cards | 94 |
| Family | 90 | Period totals work; member visualization can be richer without adding copy | 95 |
| Budgets | 89 | Useful but should share the same ring/progress language as statistics | 95 |
| Smart Quick Ledger | 90 | Candidate flow works; Android permission state is proven, visual hierarchy can be calmer | 95 |
| System Pages | 86 | Many pages use repeated `Card/ListTile` patterns; needs shared compact section system | 94 |

## Redesign Rules

1. Quick entry is only the right-side `+` at shell level. Home must not repeat a "record now" shortcut grid.
2. A screen gets one primary action. Secondary actions move to overflow, section headers, or contextual rows.
3. Theme settings expose six main colors only: green, blue, cyan, purple, orange, gray.
4. Theme color controls use compact chips with one swatch each; no stacked multi-color blocks.
5. Cards are for real grouped data, not for every page section. Avoid card-inside-card.
6. Empty states stay short: title plus one action or one sentence.
7. Financial numbers use tabular figures, right alignment where values are compared, and semantic colors only for money meaning.
8. Lists with repeated records should favor 56-72 px rows over tall decorative cards unless the row has multiple actions.
9. Heavy shadows, blur, and large animated surfaces are avoided in mobile runtime paths.
10. Every UI batch must be verified with seeded data, not only empty states.

## Implementation Batches

### Batch 1: Pollution Removal

- Remove home action rail and keep only shell `+`.
- Replace theme dropdown menus with six visible main-color chips.
- Rename theme labels to `绿色主色` style labels.
- Update tests to assert the cleaner structure.

### Batch 2: Page Rhythm

- Introduce a compact section header and dense premium row component.
- Apply it to Feature/Profile, Lending, Accounts, and system pages.
- Keep decorative accents per section, not per line.

### Batch 3: Money Surfaces

- Rework Home, Statistics, Family, Budget, and Lending summary blocks around the same metric/ring/bar language.
- Reduce chart label clutter and preserve period controls.

### Batch 4: Quick Entry Feel

- Make amount the visual focus.
- Keep required fields visible, optional fields progressive.
- Keep save action sticky and keyboard-safe.
- Profile the `+` open path for frame work and unnecessary reloads.

### Batch 5: Simulator Evidence

- Seed full showcase data.
- Capture Android and iOS screenshots for Home, Transactions, Statistics, Feature/Profile, Quick Entry, Lending, Family, Budget, and Smart Quick Ledger.
- Run `flutter analyze`, targeted widget tests, and emulator smoke.

## Acceptance

95+ means:

- No duplicate primary entry points on the same page.
- No theme/color showroom effect.
- No visible testing or explanatory copy in normal data states.
- Key pages use a shared visual rhythm.
- `+` opens quickly and does not feel blocked by unnecessary data work.
- Android and iOS simulator screenshots show real data without clipping, overlap, or noisy empty placeholders.
