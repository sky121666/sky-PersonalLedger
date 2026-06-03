#!/usr/bin/env bash

set -euo pipefail

FLUTTER_BIN="${FLUTTER_BIN:-/private/tmp/sky-personalledger-flutter-sdk/flutter/bin/flutter}"
ADB_BIN="${ADB_BIN:-adb}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOBILE_DIR="$PROJECT_ROOT/mobile"
TRACE_DIR="$PROJECT_ROOT/mobile/QA/runtime"
DEVICE_ID="${1:-}"
ROUTE_ARGS="${2:-}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
ROUTE_SECONDS="${ROUTE_SECONDS:-30}"

if ! command -v "$FLUTTER_BIN" >/dev/null 2>&1; then
  if command -v flutter >/dev/null 2>&1; then
    FLUTTER_BIN="$(command -v flutter)"
  else
    echo "[错误] FLUTTER_BIN 未配置且 PATH 中未找到 flutter。"
    exit 1
  fi
fi

if ! command -v "$ADB_BIN" >/dev/null 2>&1; then
  echo "[错误] ADB 未安装或未在 PATH。"
  echo "请先安装 Android 平台工具（platform-tools）。"
  exit 1
fi

ONLINE_DEVICES="$("$ADB_BIN" devices -l | awk 'NR>1 && $2=="device" {print $1}')"
if [ -z "$ONLINE_DEVICES" ]; then
  echo "[错误] 当前无 online 的 Android 设备。"
  echo "建议排查："
  echo " - 连接线是否支持数据传输"
  echo " - 手机是否开启 USB 调试"
  echo " - 是否弹出并确认“是否允许 USB 调试”授权"
  echo " - 运行 adb devices -l 查看状态"
  exit 2
fi

if [ -z "$DEVICE_ID" ]; then
  DEVICE_ID="$(printf '%s\n' "$ONLINE_DEVICES" | awk 'NR==1 {print $1}')"
  echo "[信息] 未传入设备 ID，自动使用首个在线设备: $DEVICE_ID"
else
  if ! printf '%s\n' "$ONLINE_DEVICES" | awk -v target="$DEVICE_ID" '$0==target {found=1} END {exit !found}'; then
    echo "[错误] 指定的设备 $DEVICE_ID 不在在线列表。"
    echo "可用设备："
    printf '%s\n' "$ONLINE_DEVICES" | sed 's/^/ - /'
    exit 3
  fi
fi

mkdir -p "$TRACE_DIR"

cd "$MOBILE_DIR"
export HOME=/tmp
export FLUTTER_SUPPRESS_ANALYTICS=true
export DART_SUPPRESS_ANALYTICS=true

DEFAULT_ROUTES=(
  "/"
  "/server-config"
  "/setup-password"
  "/login"
  "/home"
  "/transactions"
  "/statistics"
  "/profile"
  "/accounts"
  "/account-logs"
  "/profile-settings"
  "/api-tokens"
  "/security-settings"
  "/tags"
  "/templates"
  "/categories"
  "/budgets"
  "/reminders"
  "/lendings"
  "/notifications"
  "/data-management"
  "/yearly-report"
  "/family"
  "/ai-reports"
  "/quick-transaction"
)

if [ -n "$ROUTE_ARGS" ]; then
  IFS=',' read -r -a ROUTES <<< "$ROUTE_ARGS"
else
  ROUTES=("${DEFAULT_ROUTES[@]}")
fi

run_with_timeout() {
  local cmd="$1"
  local log_file="$2"

  bash -lc "$cmd" >"$log_file" 2>&1 &
  local pid=$!

  local remain=$ROUTE_SECONDS
  while [ $remain -gt 0 ]; do
    if ! kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
    sleep 1
    remain=$((remain - 1))
  done

  if kill -0 "$pid" 2>/dev/null; then
    echo "[信息] 超过 ${ROUTE_SECONDS}s，停止该路由采样。"
    kill "$pid" 2>/dev/null || true
    sleep 2
    kill -9 "$pid" 2>/dev/null || true
    return 0
  fi
  wait "$pid" 2>/dev/null || true
}

echo "============================================="
echo "Android 运行时采样闸门（profile）"
echo "时间: $(date +'%F %T')"
echo "设备: $DEVICE_ID"
echo "输出目录: $TRACE_DIR"
echo "============================================="

run_index=0
for route in "${ROUTES[@]}"; do
  run_index=$((run_index + 1))
  SAFE_ROUTE="${route//\//_}"
  SAFE_ROUTE="${SAFE_ROUTE:-root}"
  TRACE_FILE="$TRACE_DIR/startup_${TIMESTAMP}_${run_index}_${SAFE_ROUTE}.json"
  LOG_FILE="$TRACE_DIR/run_${TIMESTAMP}_${run_index}_${SAFE_ROUTE}.log"

  echo "[执行] 路由 $route"
  echo "[输出] trace=$TRACE_FILE log=$LOG_FILE"

  # 使用 trace-startup 获取第一帧启动路径，便于对比首屏时间趋势。
  # 若当前会话存在认证拦截（如登录态不足），部分路由会重定向到登录/配置页，这是正常现象，需在有登录态的测试环境下复测。
  run_with_timeout "\"$FLUTTER_BIN\" run --profile --trace-startup --trace-to-file \"$TRACE_FILE\" --device-id \"$DEVICE_ID\" --route \"$route\" --verbose" "$LOG_FILE"
  CODE=$?
  if [ "$CODE" -ne 0 ]; then
    echo "[警告] $route 采样未正常完成，查看日志: $LOG_FILE"
    tail -n 20 "$LOG_FILE" | sed 's/^/[log] /'
  else
    echo "[完成] $route"
  fi
done

echo "============================================="
echo "运行时采样已结束。请基于 trace 与 log 打分："
echo "1) 首屏目标：<= 3000ms（含认证重定向）"
echo "2) 交互目标：核心按钮响应 P99 <= 180ms（手工打点）"
echo "3) 连续滚动目标：无持续掉帧，平均 FPS >= 57"
echo "4) 在目标机上重复采样并记录分值"
echo "============================================="
