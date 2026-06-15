# Android UI95 redesign evidence - 2026-06-15

## Scope

- Backend: temporary local backend at `http://127.0.0.1:18080`.
- Android emulator URL: `http://10.0.2.2:18080`.
- iOS simulator URL: `http://127.0.0.1:18080`.
- Android device: `emulator-5554`, AVD `pld-emu-2`.
- iOS device: `iPhone 17`, iOS 26.5 simulator.
- Auth: `LEDGER_E2E_AUTO_AUTH=true` with a temporary QA password.

## Seed Data

`mobile/QA/seed_mobile_showcase_data.sh` populated:

- accounts: 8
- transactions: 10
- budgets: 5
- lendings: 2
- reminders: 2
- AI reports: 1

## Verified Screens

Screenshots were captured under:

`mobile/QA/screenshots/android/ui95-final-20260615/`

- `home.png`
- `statistics.png`
- `statistics-final.png`
- `features.png`
- `budget.png`
- `family.png`
- `family-final.png`

iOS screenshots were captured under:

`mobile/QA/screenshots/ios/ui95-final-20260615/`

- `home.png`
- `features.png`
- `family.png`
- `statistics.png`

## UI Tree Checks

- Home: bottom navigation exposes `首页`, `明细`, `统计`, `功能`; the right-side FAB exposes `记一笔`; current month expense is `¥5653.30`.
- Statistics: verified `结余`, `当月`, `今年`, `往年`, `收支趋势`, `分类排行`; expense total is `¥5653.30`; category ranking is amount-desc with `居住 ¥4200.00` before `教育 ¥980.00`.
- Features: verified compact grouped rows for `账本管理`, `计划提醒`, `智能与数据`.
- Budget: verified real total/category/member budget data without positional empty-state copy; total budget spent is `¥5653.30`, excluding system initial-balance and lending-linked transactions.
- Family: verified direct `统计` section with family budget, member ranking, and category split visible in one surface; raw relationship tokens `self/family/child` are absent and duplicate relationship labels are suppressed.

## Remaining Risk

- Android emulator is capped at 60Hz in this AVD (`androidboot.qemu.vsync=60`), so this run proves functional responsiveness and layout, not 120Hz device smoothness.
- Flutter debug launch can log skipped startup frames; final smoothness should be judged with profile/release builds on the target phone.
