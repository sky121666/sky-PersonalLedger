#!/usr/bin/env bash

set -euo pipefail

FLUTTER_BIN="${FLUTTER_BIN:-/private/tmp/sky-personalledger-flutter-sdk/flutter/bin/flutter}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if ! command -v "$FLUTTER_BIN" >/dev/null 2>&1; then
  if command -v flutter >/dev/null 2>&1; then
    FLUTTER_BIN="$(command -v flutter)"
  else
    echo "[错误] Flutter 未可用：请设置 FLUTTER_BIN 或确保 flutter 在 PATH 中。"
    exit 1
  fi
fi

echo "============================================="
echo "UI 质量闸门（静态 + 回归）"
echo "时间: $(date +'%F %T')"
echo "Flutter: $FLUTTER_BIN"
echo "项目: $PROJECT_ROOT/mobile"
echo "============================================="

cd "$PROJECT_ROOT/mobile"

echo "[步骤 1/4] 运行静态污染扫描"
HOME=/tmp "$FLUTTER_BIN" test test/ui_pollution_guard_test.dart -r compact

echo "[步骤 2/4] 运行页面静态打分脚本"
HOME=/tmp ./QA/ui_score_scan.js

echo "[步骤 3/4] 运行全量页面回归测试"
HOME=/tmp "$FLUTTER_BIN" test -r compact

echo "[步骤 4/4] 指定关键页面静态分析"
HOME=/tmp "$FLUTTER_BIN" analyze \
  lib/features/transactions/presentation/transaction_details_page.dart \
  lib/features/transactions/presentation/quick_transaction_page.dart \
  lib/features/lendings/presentation/lending_page.dart \
  lib/features/main/presentation/main_shell_page.dart \
  lib/features/home/presentation/home_page.dart

echo "============================================="
echo "结论：闸门通过。建议下一步执行运行时性能评分链路。"
echo " - Android: cd mobile && HOME=/tmp $FLUTTER_BIN run --profile -d <device_id>"
echo " - iOS: cd mobile && HOME=/tmp $FLUTTER_BIN run --profile -d <device_id>"
echo "============================================="
