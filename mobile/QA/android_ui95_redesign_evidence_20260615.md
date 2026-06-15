# Android UI95 redesign evidence - 2026-06-15

## Scope

- Backend: temporary local backend at `http://127.0.0.1:60035`.
- Emulator URL: `http://10.0.2.2:60035`.
- Device: Android emulator `emulator-5554`, AVD `pld-emu`.
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

`mobile/QA/screenshots/android/ui95-redesign-20260615/`

- `home.png`
- `statistics.png`
- `transactions.png`
- `features.png`
- `budget.png`
- `family.png`
- `quick-entry.png`

## UI Tree Checks

- Home: bottom navigation exposes `首页`, `明细`, `统计`, `功能`; the right-side FAB exposes `记一笔`.
- Statistics: verified `结余`, `当月`, `今年`, `往年`, `收支趋势`, `分类排行`; old cockpit-style labels are absent.
- Transactions: verified dense transaction list with real showcase transactions; old insight/rail labels are absent.
- Features: verified compact grouped rows for `账本管理`, `计划提醒`, `智能与数据`.
- Budget: verified real total/category/member budget data without positional empty-state copy.
- Family: verified direct `统计` section with family budget, member ranking, and category split visible in one surface.
- Quick entry: verified the main FAB opens the sheet and the sheet action uses a more-options icon instead of another visible plus.

## Remaining Risk

- Android emulator is capped at 60Hz in this AVD (`androidboot.qemu.vsync=60`), so this run proves functional responsiveness and layout, not 120Hz device smoothness.
- Family monthly spending is inflated by seeded debt/lending flows; the statistics inclusion/exclusion rule needs a separate data-accounting pass.
