#!/usr/bin/env bash

set -euo pipefail

FLUTTER_BIN="${FLUTTER_BIN:-/private/tmp/sky-personalledger-flutter-sdk/flutter/bin/flutter}"
ADB_BIN="${ADB_BIN:-adb}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MOBILE_DIR="$PROJECT_ROOT"
TRACE_DIR="$PROJECT_ROOT/QA/runtime"
GFXINFO_DIR="$TRACE_DIR/gfxinfo"
DEVICE_ID="${1:-}"
ROUTE_ARGS="${2:-}"
APP_PACKAGE="${APP_PACKAGE:-}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
ROUTE_SECONDS="${ROUTE_SECONDS:-30}"
EMULATOR_BIN="${EMULATOR_BIN:-/opt/homebrew/share/android-commandlinetools/emulator/emulator}"
ANDROID_PREFER_EMULATOR="${ANDROID_PREFER_EMULATOR:-0}"
EMULATOR_WAIT_SECONDS="${EMULATOR_WAIT_SECONDS:-120}"

resolve_app_package() {
  if [ -n "$APP_PACKAGE" ]; then
    echo "$APP_PACKAGE"
    return 0
  fi

  local gradle_file="$PROJECT_ROOT/android/app/build.gradle.kts"
  if [ -f "$gradle_file" ]; then
    APP_PACKAGE="$(sed -n '1,120p' "$gradle_file" | awk -F'\"' '/applicationId[[:space:]]*=/{print $2; exit}')"
    if [ -n "$APP_PACKAGE" ]; then
      echo "$APP_PACKAGE"
      return 0
    fi
  fi

  return 1
}

collect_gfxinfo() {
  local safe_route="$1"
  local report_path="$GFXINFO_DIR/${TIMESTAMP}_${safe_route}.txt"

  if [ -z "$APP_PACKAGE" ]; then
    return 0
  fi

  if ! "$ADB_BIN" -s "$DEVICE_ID" shell "dumpsys gfxinfo $APP_PACKAGE framestats" >"$report_path" 2>&1; then
    return 0
  fi
}

ensure_app_package() {
  if APP_PACKAGE="$(resolve_app_package)"; then
    return 0
  fi
  APP_PACKAGE=""
}

resolve_emulator_binary() {
  if [ -x "$EMULATOR_BIN" ]; then
    echo "$EMULATOR_BIN"
    return 0
  fi

  for root in "${ANDROID_SDK_ROOT:-}" "${ANDROID_HOME:-}"; do
    if [ -n "$root" ] && [ -x "$root/emulator/emulator" ]; then
      echo "$root/emulator/emulator"
      return 0
    fi
  done

  if [ -x "/opt/homebrew/share/android-commandlinetools/emulator/emulator" ]; then
    echo "/opt/homebrew/share/android-commandlinetools/emulator/emulator"
    return 0
  fi

  return 1
}

ensure_emulator_started() {
  if [ "$ANDROID_PREFER_EMULATOR" != "1" ]; then
    return 0
  fi

  if [ -n "$DEVICE_ID" ] && printf '%s\n' "$($ADB_BIN devices -l | awk 'NR>1 {print $1}' )" | awk -v target="$DEVICE_ID" '$1 == target {found=1} END {exit !found}'; then
    return 0
  fi

  local emulator_bin
  if ! emulator_bin="$(resolve_emulator_binary)"; then
    return 0
  fi

  local avd_name="${ANDROID_EMULATOR_NAME:-}"
  if [ -z "$avd_name" ]; then
    avd_name="$($emulator_bin -list-avds | awk 'NF>0 {print $1; exit}')"
  fi

  if [ -z "$avd_name" ]; then
    return 0
  fi

  if ! printf '%s\n' "$($ADB_BIN devices -l | awk 'NR>1 {print $1}')" | awk '/^emulator-/ {found=1} END {exit !found}'; then
    echo "[信息] 未检测到在线模拟器，尝试启动 $avd_name"
    "$emulator_bin" -avd "$avd_name" -no-snapshot -no-audio -no-boot-anim -gpu swiftshader_indirect >/tmp/qa_runtime_boot.log 2>&1 &
  fi
}

wait_for_device_ready() {
  local target_device="$1"
  local waited=0
  while [ "$waited" -lt "$EMULATOR_WAIT_SECONDS" ]; do
    local raw_devices
    raw_devices="$($ADB_BIN devices -l | awk 'NR>1')"

    if [ -n "$target_device" ]; then
      if printf '%s\n' "$raw_devices" | awk -v device="$target_device" '$1 == device && $2 == "device" {found=1} END {exit !found}'; then
        return 0
      fi
    elif printf '%s\n' "$raw_devices" | awk '$2 == "device" {found=1} END {exit !found}'; then
      return 0
    fi

    sleep 1
    waited=$((waited + 1))
    if [ $((waited % 10)) -eq 0 ]; then
      if [ -n "$target_device" ]; then
        echo "[信息] 正在等待目标设备就绪 ${waited}/${EMULATOR_WAIT_SECONDS}s..."
      else
        echo "[信息] 正在等待设备就绪 ${waited}/${EMULATOR_WAIT_SECONDS}s..."
      fi
    fi
  done
  return 1
}

wait_for_device_services() {
  local device="$1"
  local waited=0
  while [ "$waited" -lt "$EMULATOR_WAIT_SECONDS" ]; do
    local boot_completed
    boot_completed="$($ADB_BIN -s "$device" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
    if [ "$boot_completed" = "1" ]; then
      if "$ADB_BIN" -s "$device" shell cmd package list packages >/dev/null 2>&1; then
        return 0
      fi
    fi

    sleep 1
    waited=$((waited + 1))
    if [ $((waited % 10)) -eq 0 ]; then
      echo "[信息] 正在等待设备系统服务就绪 ${waited}/${EMULATOR_WAIT_SECONDS}s..."
    fi
  done
  return 1
}

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
  ensure_emulator_started
  sleep 2
  ONLINE_DEVICES="$($ADB_BIN devices -l | awk 'NR>1 && $2=="device" {print $1}')"
fi

if [ -z "$ONLINE_DEVICES" ]; then
  if [ -n "$DEVICE_ID" ]; then
    echo "[信息] 目标设备 $DEVICE_ID 未就绪，等待上线中（${EMULATOR_WAIT_SECONDS}s）"
  else
    echo "[信息] 未检测到在线设备，等待上线中（${EMULATOR_WAIT_SECONDS}s）"
  fi

  if ! wait_for_device_ready "$DEVICE_ID"; then
    echo "[错误] 当前无 online 的 Android 设备。"
    echo "建议排查："
    echo " - 连接线是否支持数据传输"
    echo " - 手机上是否开启开发者模式和 USB 调试"
    echo " - 是否弹出并确认“是否允许 USB 调试”授权"
    echo " - 运行 adb devices -l 查看状态"
    echo " - 模拟器未启动或启动未完成"
    echo " - 检查模拟器日志：/tmp/qa_runtime_boot.log"
    exit 2
  fi
  ONLINE_DEVICES="$($ADB_BIN devices -l | awk 'NR>1 && $2=="device" {print $1}')"
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

if ! wait_for_device_services "$DEVICE_ID"; then
  echo "[警告] 设备 $DEVICE_ID 的系统服务仍在启动（package service 未就绪）。"
  echo "建议等待 5-10 秒后重试，或确认模拟器启动完成。"
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
  local safe_route="$3"
  local start_ts
  start_ts="$(date +%s)"

  bash -lc "$cmd" >"$log_file" 2>&1 &
  local pid=$!

  local remain=$ROUTE_SECONDS
  while [ $remain -gt 0 ]; do
    if ! kill -0 "$pid" 2>/dev/null; then
      local exit_code=0
      wait "$pid"
      exit_code=$?
      ROUTE_SECONDS_ACTUAL="$(($(date +%s)-start_ts))"
      ROUTE_EXIT_CODE=$exit_code
      collect_gfxinfo "$safe_route"
      return $exit_code
    fi
    sleep 1
    remain=$((remain - 1))
  done

  if kill -0 "$pid" 2>/dev/null; then
    echo "[信息] 超过 ${ROUTE_SECONDS}s，停止该路由采样。"
    kill "$pid" 2>/dev/null || true
    sleep 2
    kill -9 "$pid" 2>/dev/null || true
    ROUTE_SECONDS_ACTUAL="$(($(date +%s)-start_ts))"
    ROUTE_EXIT_CODE=124
    collect_gfxinfo "$safe_route"
    return 124
  fi
  wait "$pid" 2>/dev/null || true
  ROUTE_SECONDS_ACTUAL="$(($(date +%s)-start_ts))"
  ROUTE_EXIT_CODE=$?
  collect_gfxinfo "$safe_route"
  return "$ROUTE_EXIT_CODE"
}

echo "============================================="
echo "Android 运行时采样闸门（profile）"
echo "时间: $(date +'%F %T')"
echo "设备: $DEVICE_ID"
echo "输出目录: $TRACE_DIR"
if [ -n "$APP_PACKAGE" ]; then
  echo "包名: $APP_PACKAGE"
fi
echo "============================================="

mkdir -p "$TRACE_DIR" "$GFXINFO_DIR"
RUNTIME_REPORT="$TRACE_DIR/runtime_report_${TIMESTAMP}.md"
echo "# Android 运行时采样报告" > "$RUNTIME_REPORT"
echo "- 时间: $(date +'%F %T')" >> "$RUNTIME_REPORT"
echo "- 设备: $DEVICE_ID" >> "$RUNTIME_REPORT"
echo "- 采样时长阈值: ${ROUTE_SECONDS}s" >> "$RUNTIME_REPORT"
echo "" >> "$RUNTIME_REPORT"
echo "| 路由 | 耗时(秒) | 状态 | 说明 |" >> "$RUNTIME_REPORT"
echo "| --- | ---: | --- | --- |" >> "$RUNTIME_REPORT"
ensure_app_package

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
  ROUTE_EXIT_CODE=0
  ROUTE_SECONDS_ACTUAL=0
  STATUS="UNKNOWN"
  CODE=0
  NOTE="未采样"
  if run_with_timeout "\"$FLUTTER_BIN\" run --profile --trace-startup --trace-to-file \"$TRACE_FILE\" --device-id \"$DEVICE_ID\" --route \"$route\" --verbose" "$LOG_FILE" "$SAFE_ROUTE"; then
    CODE=$?
    STATUS="PASS"
    NOTE="完成"
  else
    CODE=$?
    if [ "$CODE" -eq 124 ]; then
      STATUS="TIMEOUT"
      NOTE="超时停止采样（${ROUTE_SECONDS}s）"
    else
      STATUS="FAIL"
      NOTE="命令退出码 $CODE"
    fi
  fi

  if [ "$STATUS" = "PASS" ]; then
    echo "[完成] $route"
  else
    echo "[警告] $route 采样未正常完成，状态=${STATUS}，日志: $LOG_FILE"
    tail -n 20 "$LOG_FILE" | sed 's/^/[log] /'
  fi
  echo "| $route | ${ROUTE_SECONDS_ACTUAL} | ${STATUS} | ${NOTE} |" >> "$RUNTIME_REPORT"
done

echo "============================================="
echo "运行时采样报告: $RUNTIME_REPORT"
if [ -n "$APP_PACKAGE" ]; then
echo "dumpsys gfxinfo: $GFXINFO_DIR"
fi

echo "============================================="
echo "运行时采样已结束。请基于 trace 与 log 打分："
echo "1) 首屏目标：<= 3000ms（含认证重定向）"
echo "2) 交互目标：核心按钮响应 P99 <= 180ms（手工打点）"
echo "3) 连续滚动目标：无持续掉帧，平均 FPS >= 57"
echo "4) 在目标机上重复采样并记录分值"
