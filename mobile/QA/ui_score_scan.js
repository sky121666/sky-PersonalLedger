#!/usr/bin/env node
const fs = require('node:fs');
const path = require('node:path');

const cwd = process.cwd();
const mobileDir = fs.existsSync(path.join(cwd, 'test', 'ui_pollution_guard_test.dart'))
  ? cwd
  : path.join(cwd, 'mobile');
const rulesPath = path.join(mobileDir, 'test', 'ui_pollution_guard_test.dart');
const rulesSource = fs.readFileSync(rulesPath, 'utf8');

const match = rulesSource.match(/const _forbiddenUiFragments = \[(.*?)\];/s);
if (!match) {
  throw new Error(`Cannot parse forbidden fragment list from ${rulesPath}`);
}

const forbidden = [...match[1].matchAll(/'([^']*)'|\"([^\"]*)\"/g)]
  .map((x) => x[1] || x[2])
  .filter(Boolean);

const pages = [
  'features/account_logs/presentation/account_log_page.dart',
  'features/accounts/presentation/accounts_page.dart',
  'features/ai/presentation/ai_reports_page.dart',
  'features/api_tokens/presentation/api_token_page.dart',
  'features/attachments/presentation/attachment_picker_field.dart',
  'features/auth/presentation/login_page.dart',
  'features/auth/presentation/setup_password_page.dart',
  'features/bootstrap/presentation/bootstrap_page.dart',
  'features/budgets/presentation/budget_page.dart',
  'features/categories/presentation/categories_page.dart',
  'features/data_management/presentation/data_management_page.dart',
  'features/family/presentation/family_page.dart',
  'features/home/presentation/home_page.dart',
  'features/lendings/presentation/lending_page.dart',
  'features/main/presentation/main_shell_page.dart',
  'features/notifications/presentation/notification_settings_page.dart',
  'features/profile/presentation/profile_page.dart',
  'features/profile/presentation/profile_settings_page.dart',
  'features/reminders/presentation/reminder_page.dart',
  'features/reports/presentation/yearly_report_page.dart',
  'features/security/presentation/security_settings_page.dart',
  'features/server_config/presentation/server_config_page.dart',
  'features/statistics/presentation/mobile_statistics_page.dart',
  'features/tags/presentation/tag_page.dart',
  'features/templates/presentation/template_page.dart',
  'features/transactions/presentation/quick_transaction_page.dart',
  'features/transactions/presentation/transaction_details_page.dart',
];

const penaltyPerHit = 8;

const toPath = (p) => path.join(mobileDir, 'lib', p);
let totalHits = 0;
console.log('page\tviolations\tscore');
for (const page of pages) {
  const fullPath = toPath(page);
  const content = fs.readFileSync(fullPath, 'utf8');
  const hits = [];
  for (const fragment of forbidden) {
    if (content.includes(fragment)) {
      hits.push(fragment);
    }
  }
  const score = Math.max(0, 100 - hits.length * penaltyPerHit);
  totalHits += hits.length;
  console.log(`${page}\t${hits.length}\t${score}`);
}

if (totalHits > 0) {
  console.error(`❌ ui_score_scan: found ${totalHits} total static pollution hits.`);
  process.exitCode = 1;
} else {
  console.log('✅ ui_score_scan: all tracked pages are clean.');
}
