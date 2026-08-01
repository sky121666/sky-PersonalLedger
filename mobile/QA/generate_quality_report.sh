#!/usr/bin/env bash

set -euo pipefail

FLUTTER_BIN="${FLUTTER_BIN:-/private/tmp/sky-personalledger-flutter-sdk/flutter/bin/flutter}"
HOME_ENV="${HOME_ENV:-${HOME:-/private/tmp}}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
QA_DIR="$PROJECT_ROOT/mobile/QA"
REPORT_DIR="$QA_DIR/reports"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
REPORT_FILE="$REPORT_DIR/quality_audit_${TIMESTAMP}.md"
JSON_REPORT_FILE="$REPORT_DIR/quality_audit_${TIMESTAMP}.json"
TIMESTAMP_SCORE_CHECK_FILE="$REPORT_DIR/quality_scores_${TIMESTAMP}.json"
TIMESTAMP_CLEAN_CHECK_FILE="$REPORT_DIR/quality_cleanliness_${TIMESTAMP}.json"
TMP_GATE_LOG="$(mktemp)"
TMP_SCORE_REPORT="$(mktemp)"
TMP_SCORE_JSON="$(mktemp)"
TMP_SCORE_TSV="$(mktemp)"
TMP_CLEAN_REPORT="$(mktemp)"
TMP_CLEAN_JSON="$(mktemp)"
TMP_ROUTE_REPORT="$(mktemp)"
TMP_ROUTE_JSON="$(mktemp)"
TIMESTAMP_ROUTE_REPORT="$REPORT_DIR/route_quality_check_${TIMESTAMP}.md"
TIMESTAMP_ROUTE_JSON="$REPORT_DIR/route_quality_check_${TIMESTAMP}.json"

if ! command -v "$FLUTTER_BIN" >/dev/null 2>&1; then
  if command -v flutter >/dev/null 2>&1; then
    FLUTTER_BIN="$(command -v flutter)"
  else
    echo "[错误] 未找到 Flutter，可设置 FLUTTER_BIN。"
    exit 1
  fi
fi

mkdir -p "$REPORT_DIR"
cd "$PROJECT_ROOT/mobile"

# 1) 运行闸门基础链路并留存原始输出
{
  echo "============================================="
  echo "UI 质量报告生成"
  echo "时间: $(date +'%F %T')"
  echo "项目: $PROJECT_ROOT/mobile"
  echo "Flutter: $FLUTTER_BIN"
  echo "============================================="
  HOME="$HOME_ENV" "$FLUTTER_BIN" test test/ui_pollution_guard_test.dart -r compact
  HOME="$HOME_ENV" "$FLUTTER_BIN" test -r compact
  HOME="$HOME_ENV" "$FLUTTER_BIN" analyze \
    lib/features/transactions/presentation/transaction_details_page.dart \
    lib/features/transactions/presentation/quick_transaction_page.dart \
    lib/features/lendings/presentation/lending_page.dart \
    lib/features/main/presentation/main_shell_page.dart \
    lib/features/home/presentation/home_page.dart
} | tee "$TMP_GATE_LOG"

# 2) 生成逐页静态评分与 JSON 详情
set +e
HOME="$HOME_ENV" node ./QA/ui_score_scan.js > "$TMP_SCORE_TSV"
SCORE_SCAN_EXIT=$?
HOME="$HOME_ENV" node ./QA/ui_cleanliness_audit.js --json > "$TMP_CLEAN_JSON"
CLEAN_EXIT=$?
set -e

node - "$TMP_SCORE_TSV" "$TMP_SCORE_JSON" <<'NODE'
const fs = require('node:fs');

const sourcePath = process.argv[2];
const targetPath = process.argv[3];
const raw = fs.readFileSync(sourcePath, 'utf8').split(/\r?\n/).map((line) => line.trim()).filter(Boolean);

const dataLines = raw.filter((line) => line.includes('\t') && !line.startsWith('page\t') && !line.startsWith('✅') && !line.startsWith('❌'));
const minScore = 95;

const pages = dataLines.map((line) => {
  const [page, violationsStr, scoreStr] = line.split('\t');
  const violations = Number.parseInt(violationsStr || '0', 10) || 0;
  const score = Number.parseInt(scoreStr || '0', 10) || 0;
  return { page, violations, score };
}).filter((item) => item.page);

const totalPages = pages.length;
const totalViolations = pages.reduce((sum, item) => sum + item.violations, 0);
const avgScore = totalPages > 0
  ? Math.round((pages.reduce((sum, item) => sum + item.score, 0) / totalPages) * 100) / 100
  : 0;
const minCalcScore = totalPages > 0 ? Math.min(...pages.map((item) => item.score)) : 100;

const jsonData = {
  generatedAt: new Date().toISOString(),
  version: 1,
  summary: {
    totalPages,
    totalViolations,
    avgScore,
    minScore: minCalcScore,
    allPass95: pages.every((item) => item.score >= minScore),
  },
  pages,
};

fs.writeFileSync(targetPath, JSON.stringify(jsonData, null, 2));
NODE

node - <<'NODE' "$TMP_SCORE_JSON" "$TMP_CLEAN_JSON" "$JSON_REPORT_FILE" > "$TMP_SCORE_REPORT"
const fs = require('node:fs');

const scanJsonPath = process.argv[2];
const cleanJsonPath = process.argv[3];
const jsonReportPath = process.argv[4];

const scan = JSON.parse(fs.readFileSync(scanJsonPath, 'utf8'));
const clean = JSON.parse(fs.readFileSync(cleanJsonPath, 'utf8'));

const now = new Date().toISOString().slice(0, 19).replace('T', ' ');
const minScore = 95;

const scanResults = scan.pages || [];
const totalPages = scanResults.length;
const totalScanViolationPages = scanResults.filter((r) => (r.violations || 0) > 0).length;
const totalScanViolations = scanResults.reduce((sum, r) => sum + (r.violations || 0), 0);
const avgScanScore = totalPages
  ? Math.round(scanResults.reduce((sum, r) => sum + (r.score || 0), 0) / totalPages * 100) / 100
  : 0;
const minScanScore = totalPages ? Math.min(...scanResults.map((r) => r.score || 0)) : 100;
const scanPass = scanResults.every((r) => (r.score || 0) >= minScore);

const cleanRows = clean.rows || [];
const avgCleanScore = Number(clean.average || 0);
const minCleanScore = Number(clean.minScore || 0);
const cleanPass = minCleanScore >= minScore;

const jsonData = {
  generatedAt: new Date().toISOString(),
  meta: {
    project: `${process.cwd()}`,
    ruleSource: 'ui_score_scan + ui_cleanliness_audit (auto-discovered pages)',
    totalPages,
  },
  summary: {
    allPass95: scanPass && cleanPass,
    scan: {
      allPass95: scanPass,
      minScore: minScanScore,
      avgScore: avgScanScore,
      totalViolations: totalScanViolations,
      violationPages: totalScanViolationPages,
    },
    cleanliness: {
      allPass95: cleanPass,
      minScore: minCleanScore,
      avgScore: avgCleanScore,
    },
    totalPages,
  },
  pages: scanResults,
  cleanliness: clean,
};
fs.writeFileSync(jsonReportPath, JSON.stringify(jsonData, null, 2));

console.log(`# 移动端界面质量审计报表`);
console.log(`- 时间: ${now}`);
console.log(`- 工程: ${process.cwd()}`);
console.log("- 规则来源: `mobile/QA/ui_score_scan.js + ui_cleanliness_audit.js`（自动发现页面）");
console.log(`- 页面数: ${totalPages}`);
console.log(`- 命中页数: ${totalScanViolationPages}`);
console.log(`- 触发总计: ${totalScanViolations}`);
console.log(`- 最低分: ${minScanScore}`);
console.log(`- 平均分: ${avgScanScore}`);
console.log(`- 结论: ${scanPass && cleanPass ? '全部页面满足 95+ 目标（当前规则下）' : '部分页面未达 95，需要清理'}`);
console.log('');
console.log('| 页面 | 污染命中 | 评分 |');
console.log('| --- | ---: | ---: |');
for (const item of scanResults) {
  console.log(`| ${item.page} | ${item.violations || 0} | ${item.score || 0} |`);
}
if (!scanPass || !cleanPass) {
  console.log('');
  if (!scanPass) {
    console.log('### 需处理项（静态禁用词）');
    for (const item of scanResults) {
      if ((item.score || 0) < minScore) {
        const details = (item.matchedFragments || []).join('；');
        console.log(`- ${item.page}：${item.violations || 0} 项（${details}）`);
      }
    }
  }
  if (!cleanPass) {
    console.log('### 需处理项（界面清洁度）');
    for (const item of cleanRows) {
      if ((item.score || 0) < minScore) {
        console.log(`- ${item.page}：score ${item.score}（helper=${item.helper || 0}, longText=${item.longText || 0}, action=${item.action || 0}, totalPenalty=${item.totalPenalty || 0}）`);
      }
    }
  }
}
console.log('');
console.log('## 界面清洁度评分（静态）');
console.log(`- 平均分: ${avgCleanScore}`);
console.log(`- 最低分: ${minCleanScore}`);
console.log('| 页面 | 分数 | helper | longText | action | 总扣分 |');
console.log('| --- | ---: | ---: | ---: | ---: | ---: |');
for (const item of cleanRows) {
  console.log(
    `| ${item.page} | ${item.score} | ${item.helper || 0} | ${item.longText || 0} | ${item.action || 0} | ${item.totalPenalty || 0} |`,
  );
}
console.log(`\n> 规则阈值：score < ${minScore} 判定未达标；每项污染或清洁扣分按对应规则。`);
NODE

if [ "$SCORE_SCAN_EXIT" -ne 0 ]; then
  echo "[警告] ui_score_scan 发现污染，已继续产出报告：$TMP_SCORE_JSON"
fi
if [ "$CLEAN_EXIT" -ne 0 ]; then
  echo "[警告] ui_cleanliness_audit 发现清洁度不足，已继续产出报告：$TMP_CLEAN_JSON"
fi

cat "$TMP_SCORE_REPORT" > "$REPORT_FILE"

# 3) 路由级评分（静态评分闭环）
# 优先使用清洁度评分结果（更严格的版面约束）进行路由关联验证
set +e
node ./QA/route_quality_matrix.js "$TMP_CLEAN_JSON" "$TMP_ROUTE_REPORT" "$TMP_ROUTE_JSON"
ROUTE_MATRIX_EXIT=$?
set -e
if [ "$ROUTE_MATRIX_EXIT" -ne 0 ]; then
  echo "[警告] 路由级评分未闭环，请先修复路由映射与分数不足项。"
fi

if [ -s "$TMP_ROUTE_REPORT" ]; then
  cat "$TMP_ROUTE_REPORT" >> "$REPORT_FILE"
  cp "$TMP_ROUTE_REPORT" "$TIMESTAMP_ROUTE_REPORT"
  ln -sfn "$TIMESTAMP_ROUTE_REPORT" "$REPORT_DIR/route_quality_check_latest.md"
  ln -sfn "$TIMESTAMP_ROUTE_REPORT" "$QA_DIR/route_quality_check_latest.md"
fi

if [ -s "$TMP_ROUTE_JSON" ]; then
  node - "$JSON_REPORT_FILE" "$TMP_ROUTE_JSON" "$TMP_CLEAN_JSON" <<'NODE'
const fs = require('node:fs');
const reportPath = process.argv[2];
const routeReportPath = process.argv[3];
const cleanReportPath = process.argv[4];

const report = JSON.parse(fs.readFileSync(reportPath, 'utf8'));
const routeReport = JSON.parse(fs.readFileSync(routeReportPath, 'utf8'));
const cleanReport = JSON.parse(fs.readFileSync(cleanReportPath, 'utf8'));

report.routeQuality = routeReport;
report.summary.routeQuality = {
  totalRoutes: routeReport.summary.totalRoutes || 0,
  mappedRoutes: routeReport.summary.mappedRoutes || 0,
  missingRoutes: routeReport.summary.missingRoutes || 0,
  allPass95: !!routeReport.summary.allPass95,
  minScore: routeReport.summary.minScore || 95,
};
report.cleanliness = cleanReport;
report.summary.cleanliness = {
  average: cleanReport.average || 0,
  minScore: cleanReport.minScore || 0,
  allPass95: (cleanReport.minScore || 0) >= 95,
};
fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));
NODE
  cp "$TMP_ROUTE_JSON" "$TIMESTAMP_ROUTE_JSON"
  ln -sfn "$TIMESTAMP_ROUTE_JSON" "$REPORT_DIR/route_quality_check_latest.json"
  ln -sfn "$TIMESTAMP_ROUTE_JSON" "$QA_DIR/route_quality_check_latest.json"
fi

cp "$JSON_REPORT_FILE" "$TIMESTAMP_SCORE_CHECK_FILE"
cp "$TMP_CLEAN_JSON" "$TIMESTAMP_CLEAN_CHECK_FILE"
ln -sfn "$JSON_REPORT_FILE" "$QA_DIR/quality_scores_latest_check.json"
ln -sfn "$TIMESTAMP_CLEAN_CHECK_FILE" "$QA_DIR/quality_cleanliness_latest_check.json"
ln -sfn "$JSON_REPORT_FILE" "$QA_DIR/quality_audit_latest.json"
ln -sfn "$REPORT_FILE" "$QA_DIR/quality_audit_latest.md"

node - "$JSON_REPORT_FILE" <<'NODE'
const fs = require('node:fs');
const reportPath = process.argv[2];
const data = JSON.parse(fs.readFileSync(reportPath, 'utf8'));
if (!data.summary.allPass95) {
  process.exitCode = 1;
}
NODE
SCORE_PASS=$?

# 4) 追加设备链路状态（不阻塞）
ADB_OUTPUT="$(command -v adb >/dev/null 2>&1 && adb devices -l || true)"
ANDROID_DEVICE_LINE_COUNT="$(printf '%s\n' "$ADB_OUTPUT" | awk 'NR>1 && $2=="device" {count++} END {print count+0}')"
ANDROID_DEVICE_INFO="$(printf '%s\n' "$ADB_OUTPUT" | awk 'NR>1 && ($2=="device" || $2=="offline" || $2=="unauthorized") {print $0}')"
FLUTTER_DEVICES_OUTPUT="$(HOME="$HOME_ENV" "$FLUTTER_BIN" devices 2>&1 || true)"

{
  echo ""
  echo "## 安装与运行链路状态"
  echo "- 生成时间: $TIMESTAMP"
  echo "- Android 设备状态:"
  if [ -n "$ANDROID_DEVICE_INFO" ]; then
    echo "$ANDROID_DEVICE_INFO" | awk '{print "- "$0}'
  else
    echo "- 未检测到在线/可见设备（adb devices -l）"
  fi
  echo "- Android 在线设备数: ${ANDROID_DEVICE_LINE_COUNT:-0}"
  echo "- iOS/Flutter 设备列表:"
  echo "$FLUTTER_DEVICES_OUTPUT" | awk 'NF > 0 {print "- "$0}'
  echo "- 质量闸门日志: $TMP_GATE_LOG"
  echo "- JSON 详情: $JSON_REPORT_FILE"
} >> "$REPORT_FILE"

mkdir -p "$REPORT_DIR"
ln -sfn "$JSON_REPORT_FILE" "$REPORT_DIR/quality_audit_latest.json"
echo "[完成] 已生成报告: $REPORT_FILE"
cat "$REPORT_FILE"
rm -f "$TMP_GATE_LOG" "$TMP_SCORE_REPORT" "$TMP_SCORE_JSON" "$TMP_SCORE_TSV" "$TMP_CLEAN_REPORT" "$TMP_CLEAN_JSON"
rm -f "$TMP_ROUTE_REPORT" "$TMP_ROUTE_JSON"

if [ "$SCORE_PASS" -ne 0 ] || [ "$ROUTE_MATRIX_EXIT" -ne 0 ]; then
  echo "[失败] 静态评分未达到 95+。请先按报告逐项清理。"
  exit 2
fi
