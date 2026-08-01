# Android UI Redesign Evidence 2026-06-15

## Environment

- Emulator: `emulator-5554`, AVD `pld-emu`
- Backend: `http://127.0.0.1:60033`
- Android backend URL: `http://10.0.2.2:60033`
- Password used for QA: `LedgerE2ePass123!`
- APK: `mobile/build/app/outputs/flutter-apk/app-debug.apk`

## Seed Data

`mobile/QA/seed_mobile_showcase_data.sh` completed with:

- accounts: 8
- transactions: 10
- budgets: 5
- lendings: 2
- reminders: 2
- ai_reports: 1

## Screenshots

- `mobile/QA/screenshots/android/ui-redesign-20260615/home-after-redesign.png`
- `mobile/QA/screenshots/android/ui-redesign-20260615/profile-compact-entries.png`
- `mobile/QA/screenshots/android/ui-redesign-20260615/profile-theme-main-colors.png`
- `mobile/QA/screenshots/android/ui-redesign-20260615/lending-remaining-label.png`
- `mobile/QA/screenshots/android/ui-redesign-20260615/quick-entry-plus-sheet.png`

## UI Tree Checks

Home:

- `首页`: present
- `净资产`: present
- `当月现金流`: present
- `最近交易`: present

Feature/Profile:

- `账本管理`: present
- `计划提醒`: present
- `智能与数据`: present
- `借贷往来`: present
- Old pollution text absent: `功能中心`, `能力入口`, `主题模板`, `个人控制中枢`

Theme:

- `主色`: present
- `绿色主色`, `蓝色主色`, `青色主色`, `紫色主色`, `橙色主色`, `灰色主色`: present
- Old theme-market text absent: `主题星图`, `推荐主题策展`, `模板矩阵`, `体验定位`

Lending:

- `借贷往来`: present
- `往来金额`: present
- `应收`: present
- `应付`: present
- `张三`: present
- `剩余`: present
- `¥5,000.00`, `¥8,000.00`: present

Quick entry:

- Opened from right-side `+`
- `记一笔`: present
- `账户`: present
- `分类`: present
- `时间`: present
- `支出`, `收入`, `转账`: present

## Remaining Gaps

- iOS simulator screenshot pass still needs to be refreshed after the same UI changes.
- Quick entry performance still needs a dedicated frame timing run after reinstalling the build that includes the `+` semantic label.
- Statistics, Family, Budget, Transactions and secondary system pages still need the same compact rhythm audit before calling the 95+ goal complete.
