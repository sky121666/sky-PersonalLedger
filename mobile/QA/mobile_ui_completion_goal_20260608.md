# Mobile UI completion goal - 2026-06-08

## Conclusion

Current mobile UI cleanliness has reached the 95+ acceptance target under the static audit rules. The next full-quality target is not to remove more features, but to keep the functional surface complete while making every page visually quiet, data-realistic, and simulator-verifiable.

Target score: **98/100 current acceptance**, **100/100 remaining goal after runtime proof and large-data polish**.

## Product direction

- Keep the Web feature set mapped into mobile: accounts, transactions, statistics, lending, categories, budgets, reminders, attachments, data management, family, AI reports, API tokens, security, yearly report, and profile settings.
- Remove UI pollution: repeated helper copy, tutorial-like text, duplicate buttons, decorative labels that do not help the task, and mock-only empty banners.
- Keep a premium visual layer: restrained color, clear iconography, spacing rhythm, high-density cards, and decorative accents only when they improve hierarchy.
- Keep primary recording action as a right-side `+` entry; do not expose verbose "record transaction" labels in the main shell.
- Theme colors should use direct color names only. Do not show redundant tone labels such as "stable", "clear", or "low-key".

## Page acceptance matrix

| Area | Route/page | Current score | Acceptance state | Remaining full-score risk |
| --- | --- | ---: | --- | --- |
| Bootstrap | `/` | 100 | PASS | None in static scan |
| Server config | `/server-config` | 100 | PASS | Runtime address entry must stay emulator-aware |
| Login | `/login` | 100 | PASS | Authenticated traversal still needs a known test password |
| Password setup | `/setup-password` | 100 | PASS | None in static scan |
| Home | `/home` | 100 | PASS | Very large money values need final small-screen fit proof |
| Transactions | `/transactions` | 100 | PASS | Filter/detail density needs screenshot regression coverage |
| Quick transaction | `/quick-transaction` | 100 | PASS | Attachment action must remain one compact `+` |
| Statistics | `/statistics` | 100 | PASS | Chart density needs runtime screenshot review |
| Lending | `/lendings` | 100 | PASS | Large lending cards need continued visual regression coverage |
| Accounts | `/accounts` | 100 | PASS | None in static scan |
| Account logs | `/account-logs` | 100 | PASS | None in static scan |
| Categories | `/categories` | 100 | PASS | Header must stay compact, no helper copy relapse |
| Tags | `/tags` | 100 | PASS | None in static scan |
| Templates | `/templates` | 100 | PASS | None in static scan |
| Budgets | `/budgets` | 100 | PASS | None in static scan |
| Reminders | `/reminders` | 100 | PASS | None in static scan |
| Notifications | `/notifications` | 100 | PASS | None in static scan |
| Data management | `/data-management` | 100 | PASS | Keep actions grouped, no explanatory clutter |
| Family | `/family` | 100 | PASS | None in static scan |
| AI reports | `/ai-reports` | 100 | PASS | Keep AI state useful, not promotional |
| API tokens | `/api-tokens` | 100 | PASS | Security copy must stay concise |
| Security | `/security-settings` | 100 | PASS | None in static scan |
| Yearly report | `/yearly-report` | 100 | PASS | Chart screenshot coverage still useful |
| Profile | `/profile` | 100 | PASS | Theme selector must avoid excessive palette blocks |
| Profile settings | `/profile-settings` | 100 | PASS | Color naming must remain simple |
| Attachments | `AttachmentPickerField` | 100 | PASS | Header action must remain compact |

## Verification evidence

- Static UI pollution audit: `mobile/QA/reports/quality_audit_20260608_020014.md`
- Route matrix: `mobile/QA/reports/route_quality_check_20260608_020014.md`
- Current screenshot corpus: `mobile/QA/screenshots/current/`
- Android emulator gate: `mobile/QA/android_ui_gate_20260608.md`
- Android emulator proof screenshot: `mobile/QA/screenshots/android/android-emulator-install-launch-settled-20260608.png`
- Real backend E2E: `mobile/QA/mobile_real_backend_e2e_20260608.md`
- Performance acceptance: `mobile/QA/mobile_performance_acceptance_20260608.md`

## Android policy

Android QA must use an emulator by default.

- Default target class: `emulator-*`
- Current AVD used in evidence: `pld-emu-2`, serial `emulator-5554`
- Host backend URL: `http://127.0.0.1:8080`
- Emulator backend URL: `http://10.0.2.2:8080`
- Scripts must not silently install to a physical Android phone unless explicitly overridden.

## Score

- UI pollution / static cleanliness: **100/100**
- Route coverage: **100/100**
- Current screenshot coverage: **98/100**
- Real backend full flow: **100/100**
- Android emulator smoke: **98/100**
- iOS simulator smoke: **98/100**
- Runtime performance proof: **92/100**, because frame/tap evidence exists, but the full-site runtime score is still below 95.

Overall current score: **98/100**.

To reach 100/100, the remaining work is:

- Add small-screen proof for very large money values so real financial data never truncates awkwardly.
- Keep iOS and Android screenshot snapshots refreshed from the same seeded data set.
- Split full Android mutation E2E into smaller emulator tests so the route-level performance report can complete reliably.
- Produce stable `dumpsys gfxinfo` reports for home, transactions, statistics, lending, and quick transaction.
