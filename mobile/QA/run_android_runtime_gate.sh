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
FLUTTER_NO_DDS_DEFAULT="${FLUTTER_NO_DDS_DEFAULT:-1}"
FLUTTER_DISABLE_SERVICE_AUTH_CODES="${FLUTTER_DISABLE_SERVICE_AUTH_CODES:-1}"
FLUTTER_RETRY_ON_DDS_FAILURE="${FLUTTER_RETRY_ON_DDS_FAILURE:-1}"
FLUTTER_USE_TRACE_STARTUP="${FLUTTER_USE_TRACE_STARTUP:-0}"
FLUTTER_TRACE_FALLBACK="${FLUTTER_TRACE_FALLBACK:-1}"

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

collect_trace_artifact() {
  local host_trace_file="$1"
  local device_trace_file="$2"
  local safe_route="$3"

  if [ -z "$host_trace_file" ] || [ -z "$device_trace_file" ] || [ -z "$DEVICE_ID" ]; then
    return 1
  fi

  if [ -n "$APP_PACKAGE" ]; then
    if ! "$ADB_BIN" -s "$DEVICE_ID" shell "run-as \"$APP_PACKAGE\" test -f \"$device_trace_file\"" >/dev/null 2>&1; then
      echo "[警告] $safe_route trace 未回传: 设备端未生成 $device_trace_file"
      return 1
    fi
  elif ! "$ADB_BIN" -s "$DEVICE_ID" shell "test -f \"$device_trace_file\" && ls -l \"$device_trace_file\"" >/dev/null 2>&1; then
    echo "[警告] $safe_route trace 未回传: 设备端未生成 $device_trace_file"
    return 1
  fi

  if [ -n "$APP_PACKAGE" ]; then
    if "$ADB_BIN" -s "$DEVICE_ID" shell "run-as \"$APP_PACKAGE\" cat \"$device_trace_file\"" >"$host_trace_file" 2>/dev/null; then
      "$ADB_BIN" -s "$DEVICE_ID" shell "run-as \"$APP_PACKAGE\" rm -f \"$device_trace_file\"" >/dev/null 2>&1 || true
      return 0
    fi
    "$ADB_BIN" -s "$DEVICE_ID" shell "run-as \"$APP_PACKAGE\" rm -f \"$device_trace_file\"" >/dev/null 2>&1 || true
    echo "[警告] $safe_route trace 回传失败: run-as cat 失败"
    return 1
  fi

  if ! "$ADB_BIN" -s "$DEVICE_ID" shell "test -f \"$device_trace_file\" && ls -l \"$device_trace_file\"" >/dev/null 2>&1; then
    echo "[警告] $safe_route trace 未回传: 设备端未生成 $device_trace_file"
    return 1
  fi

  mkdir -p "$(dirname "$host_trace_file")"
  if "$ADB_BIN" -s "$DEVICE_ID" pull "$device_trace_file" "$host_trace_file" >/dev/null 2>&1; then
    "$ADB_BIN" -s "$DEVICE_ID" shell "rm -f \"$device_trace_file\"" >/dev/null 2>&1 || true
    return 0
  fi

  "$ADB_BIN" -s "$DEVICE_ID" shell "rm -f \"$device_trace_file\"" >/dev/null 2>&1 || true
  return 1
}

stop_app_instance() {
  if [ -z "$APP_PACKAGE" ]; then
    return 0
  fi

  if [ -z "$DEVICE_ID" ]; then
    return 0
  fi

  "$ADB_BIN" -s "$DEVICE_ID" shell "am force-stop $APP_PACKAGE" >/dev/null 2>&1 || true
}

terminate_process_tree() {
  local pid="$1"

  if [ -z "$pid" ]; then
    return 0
  fi

  local child_pids
  child_pids="$(pgrep -P "$pid" || true)"
  for child in $child_pids; do
    kill -TERM "$child" 2>/dev/null || true
  done
  sleep 1
  for child in $child_pids; do
    kill -KILL "$child" 2>/dev/null || true
  done

  kill -TERM "$pid" 2>/dev/null || true
  sleep 1
  kill -KILL "$pid" 2>/dev/null || true
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
  local timeout_secs="${4:-$ROUTE_SECONDS}"
  local elapsed=0
  local start_ts
  start_ts="$(date +%s)"

  bash -lc "$cmd" >"$log_file" 2>&1 &
  local pid=$!

  local remain="$timeout_secs"
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
    elapsed=$((elapsed + 1))
    if [ $((elapsed % 10)) -eq 0 ]; then
      echo "[进度] $safe_route 已运行 ${elapsed}s..."
    fi
    remain=$((remain - 1))
  done

  if kill -0 "$pid" 2>/dev/null; then
      echo "[信息] 超过 ${timeout_secs}s，停止该路由采样。"
    terminate_process_tree "$pid"
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

build_run_command() {
  local trace_file="$1"
  local route="$2"
  local no_dds="$3"
  local use_trace="$4"

  local cmd="\"$FLUTTER_BIN\" run --profile --no-hot --no-resident --device-id \"$DEVICE_ID\" --route \"$route\""
  if [ "$use_trace" = "1" ]; then
    cmd+=" --trace-startup --trace-to-file \"$trace_file\""
  fi

  if [ "$FLUTTER_DISABLE_SERVICE_AUTH_CODES" = "1" ]; then
    cmd+=" --disable-service-auth-codes"
  fi
  if [ "$no_dds" = "1" ]; then
    cmd+=" --no-dds"
  fi

  cmd+=" --verbose"
  echo "$cmd"
}

is_trace_related_crash() {
  local log_file="$1"
  if grep -qE "Perfettofile|A recorder of type \"Perfettofile\" is currently in use|getVMTimeline|Could not find an option named \"--timeout\"|Timeline.*not be retrieved|The timeline related request could not be completed|log reader stopped unexpectedly|Error waiting for a debug connection|trace-startup" "$log_file" 2>/dev/null; then
    return 0
  fi
  return 1
}

route_started() {
  local log_file="$1"
  if grep -qE "Launching lib/main.dart|Application launch failed|Installing APK|Syncing files|Debug service listening|Installing build/app/outputs|Installing APK\.|Performing Streamed Install|Starting: Intent" "$log_file" 2>/dev/null; then
    return 0
  fi
  return 1
}

should_retry_with_alternate() {
  local log_file="$1"
  local no_dds_used="$2"
  local fail_code="$3"

  if [ "$FLUTTER_RETRY_ON_DDS_FAILURE" != "1" ]; then
    return 1
  fi

  if [ "$fail_code" -eq 124 ]; then
    return 1
  fi

  if [ "$no_dds_used" = "1" ]; then
    if grep -qE "(Error waiting for a debug connection|Failed to start Dart Development Service|Failed to establish service protocol|DDS failed|Failed to open timeline file)" "$log_file" 2>/dev/null; then
      return 0
    fi
    return 1
  fi

  if grep -qE "(Error waiting for a debug connection|Failed to start Dart Development Service|Failed to establish service protocol|DDS failed|Failed to open timeline file)" "$log_file" 2>/dev/null; then
    return 0
  fi

  return 1
}

echo "============================================="
echo "Android 运行时采样闸门（profile）"
echo "时间: $(date +'%F %T')"
echo "设备: $DEVICE_ID"
echo "输出目录: $TRACE_DIR"
if [ "$FLUTTER_USE_TRACE_STARTUP" = "1" ]; then
  echo "Trace-Startup: 启用"
else
  echo "Trace-Startup: 关闭（默认）"
fi
if [ "$FLUTTER_TRACE_FALLBACK" = "1" ]; then
  echo "Trace 回退: 启用"
else
  echo "Trace 回退: 关闭"
fi
if [ -n "$APP_PACKAGE" ]; then
  echo "包名: $APP_PACKAGE"
fi
echo "============================================="

mkdir -p "$TRACE_DIR" "$GFXINFO_DIR"
RUNTIME_REPORT="$TRACE_DIR/runtime_report_${TIMESTAMP}.md"
RUNTIME_REPORT_LATEST="$TRACE_DIR/runtime_report_latest.md"
echo "# Android 运行时采样报告" > "$RUNTIME_REPORT"
echo "- 时间: $(date +'%F %T')" >> "$RUNTIME_REPORT"
echo "- 设备: $DEVICE_ID" >> "$RUNTIME_REPORT"
echo "- 采样时长阈值: ${ROUTE_SECONDS}s" >> "$RUNTIME_REPORT"
echo "" >> "$RUNTIME_REPORT"
echo "| 路由 | 耗时(秒) | 状态 | 说明 |" >> "$RUNTIME_REPORT"
echo "| --- | ---: | --- | --- |" >> "$RUNTIME_REPORT"
TRACE_DEVICE_BASE_DIR="/data/local/tmp"
ensure_app_package
if [ -n "$APP_PACKAGE" ]; then
  TRACE_DEVICE_BASE_DIR="/data/data/$APP_PACKAGE/files"
fi

run_index=0
for route in "${ROUTES[@]}"; do
  run_index=$((run_index + 1))
  SAFE_ROUTE="${route//\//_}"
  SAFE_ROUTE="${SAFE_ROUTE:-root}"
  TRACE_FILE_HOST="$TRACE_DIR/startup_${TIMESTAMP}_${run_index}_${SAFE_ROUTE}.json"
  TRACE_FILE_DEVICE="${TRACE_DEVICE_BASE_DIR}/startup_${TIMESTAMP}_${run_index}_${SAFE_ROUTE}.json"
  LOG_FILE="$TRACE_DIR/run_${TIMESTAMP}_${run_index}_${SAFE_ROUTE}.log"
  TRACE_ENABLED=1
  if [ "$FLUTTER_USE_TRACE_STARTUP" != "1" ]; then
    TRACE_ENABLED=0
  fi
  TRACE_FILE_CAPTURED=0
  TRACE_FILE_2_HOST=""
  TRACE_FILE_2_DEVICE=""
  TRACE_FILE_2_ENABLED=0

  echo "[执行] 路由 $route"
  if [ "$TRACE_ENABLED" = "1" ]; then
    echo "[输出] trace=$TRACE_FILE_HOST log=$LOG_FILE"
    echo "[输出] 设备端 trace=$TRACE_FILE_DEVICE"
  else
    echo "[输出] trace=（未启用） log=$LOG_FILE"
  fi
  stop_app_instance

  # 使用 trace-startup 获取第一帧启动路径，便于对比首屏时间趋势。
  # 若当前会话存在认证拦截（如登录态不足），部分路由会重定向到登录/配置页，这是正常现象，需在有登录态的测试环境下复测。
  ROUTE_EXIT_CODE=0
  ROUTE_SECONDS_ACTUAL=0
  STATUS="UNKNOWN"
  CODE=0
  NOTE="未采样"
  PRIMARY_NO_DDS="$FLUTTER_NO_DDS_DEFAULT"
  CMD="$(build_run_command "$TRACE_FILE_DEVICE" "$route" "$PRIMARY_NO_DDS" "$TRACE_ENABLED")"
  echo "[命令] $CMD"

  if run_with_timeout "$CMD" "$LOG_FILE" "$SAFE_ROUTE"; then
    CODE=$?
    STATUS="PASS"
    NOTE="完成"
  else
    CODE=$?
    if [ "$CODE" -eq 124 ] && [ "$TRACE_ENABLED" = "1" ] && [ "$FLUTTER_TRACE_FALLBACK" = "1" ]; then
      TRACE_ENABLED=0
      CMD="$(build_run_command "" "$route" "$PRIMARY_NO_DDS" "0")"
      FALLBACK_TIMEOUT=$((ROUTE_SECONDS * 2))
      echo "[修复] trace-startup 超时，回退到无 trace 采样"
      if run_with_timeout "$CMD" "$LOG_FILE" "$SAFE_ROUTE" "$FALLBACK_TIMEOUT"; then
        CODE=$?
        if route_started "$LOG_FILE"; then
          STATUS="PASS"
          NOTE="完成（超时回退无 trace）"
        else
          STATUS="TIMEOUT"
          NOTE="超时回退无 trace 后未检测到启动日志"
        fi
      else
        CODE=$?
        if [ "$CODE" -eq 124 ] && route_started "$LOG_FILE"; then
          STATUS="TIMEOUT"
          NOTE="超时停止采样（${FALLBACK_TIMEOUT}s），回退到无 trace"
        else
          STATUS="FAIL"
          NOTE="回退无 trace 失败（码 $CODE）"
        fi
      fi
    elif is_trace_related_crash "$LOG_FILE" && [ "$FLUTTER_TRACE_FALLBACK" = "1" ] && [ "$TRACE_ENABLED" = "1" ]; then
      TRACE_ENABLED=0
      CMD="$(build_run_command "" "$route" "$PRIMARY_NO_DDS" "0")"
      FALLBACK_TIMEOUT=$((ROUTE_SECONDS * 2))
      echo "[修复] trace-startup 链路异常，回退到无 trace 采样"
      if run_with_timeout "$CMD" "$LOG_FILE" "$SAFE_ROUTE" "$FALLBACK_TIMEOUT"; then
        CODE=$?
        if route_started "$LOG_FILE"; then
          STATUS="PASS"
          NOTE="完成（回退无 trace）"
        else
          STATUS="FAIL"
          NOTE="回退无 trace 后未检测到启动日志"
        fi
      else
        CODE=$?
        if [ "$CODE" -eq 124 ] && route_started "$LOG_FILE"; then
          STATUS="TIMEOUT"
          NOTE="超时停止采样（${FALLBACK_TIMEOUT}s），回退到无 trace"
        else
          STATUS="FAIL"
          NOTE="回退无 trace 失败（码 $CODE）"
        fi
      fi
    elif should_retry_with_alternate "$LOG_FILE" "$PRIMARY_NO_DDS" "$CODE"; then
      if [ "$PRIMARY_NO_DDS" = "1" ]; then
        RETRY_NO_DDS=0
        NOTE="检测到异常，切换参数重试（--no-dds=0）"
      else
        RETRY_NO_DDS=1
        NOTE="检测到DDS通道异常，切换参数重试（--no-dds=1）"
      fi

      TRACE_FILE_2_HOST="${TRACE_FILE_HOST%.json}-retry.json"
      TRACE_FILE_2_DEVICE="${TRACE_DEVICE_BASE_DIR}/startup_${TIMESTAMP}_${run_index}_${SAFE_ROUTE}_retry.json"
      TRACE_FILE_2_ENABLED=1
      LOG_FILE_2="${LOG_FILE%.log}-retry.log"
      CMD_2="$(build_run_command "$TRACE_FILE_2_DEVICE" "$route" "$RETRY_NO_DDS" "1")"
      echo "[命令] $CMD_2"
      echo "[重试] $route 使用参数重试采样（--no-dds=$RETRY_NO_DDS）"
      echo "[重试输出] trace=$TRACE_FILE_2_HOST log=$LOG_FILE_2"
      if run_with_timeout "$CMD_2" "$LOG_FILE_2" "${SAFE_ROUTE}_retry"; then
        CODE=$?
        STATUS="PASS"
        NOTE="重试完成（--no-dds=$RETRY_NO_DDS）"
      else
        CODE=$?
        NOTE="重试后仍失败（码 $CODE）"
      fi
      if is_trace_related_crash "$LOG_FILE_2" && [ "$FLUTTER_TRACE_FALLBACK" = "1" ]; then
        TRACE_FILE_2_ENABLED=0
        CMD_2="$(build_run_command "" "$route" "$RETRY_NO_DDS" "0")"
        if run_with_timeout "$CMD_2" "$LOG_FILE_2" "${SAFE_ROUTE}_retry"; then
          CODE=$?
          if route_started "$LOG_FILE_2"; then
            STATUS="PASS"
            NOTE="重试后 trace 异常，回退无 trace 完成"
          else
            STATUS="FAIL"
            NOTE="重试后 trace 异常，回退无 trace 未启动"
          fi
        else
          CODE=$?
          if [ "$CODE" -eq 124 ] && route_started "$LOG_FILE_2"; then
            STATUS="TIMEOUT"
            NOTE="重试后 trace 异常，超时停止采样（${ROUTE_SECONDS}s）"
          else
            STATUS="FAIL"
            NOTE="重试后仍失败（码 $CODE）"
          fi
        fi
      fi
    fi

    if [ "$CODE" -eq 124 ] && [ "$STATUS" = "UNKNOWN" ]; then
      STATUS="TIMEOUT"
      NOTE="超时停止采样（${ROUTE_SECONDS}s）"
    elif [ "$STATUS" = "UNKNOWN" ]; then
      STATUS="FAIL"
      NOTE="${NOTE:-命令退出码 $CODE}"
    fi
  fi

  if [ "$TRACE_ENABLED" = "1" ]; then
    if collect_trace_artifact "$TRACE_FILE_HOST" "$TRACE_FILE_DEVICE" "$SAFE_ROUTE"; then
      TRACE_FILE_CAPTURED=1
    fi
  fi
  if [ "$TRACE_FILE_2_ENABLED" = "1" ] && [ -n "${TRACE_FILE_2_HOST:-}" ] && [ -n "${TRACE_FILE_2_DEVICE:-}" ]; then
    if collect_trace_artifact "$TRACE_FILE_2_HOST" "$TRACE_FILE_2_DEVICE" "${SAFE_ROUTE}_retry"; then
      TRACE_FILE_CAPTURED=1
      TRACE_FILE_HOST="$TRACE_FILE_2_HOST"
    fi
  fi
  if [ "$TRACE_FILE_CAPTURED" -eq 1 ]; then
    echo "[输出] trace 已回传: $TRACE_FILE_HOST"
  fi
  if [ "$CODE" -eq 124 ] && [ "$TRACE_FILE_CAPTURED" -eq 1 ] && [ "$STATUS" = "TIMEOUT" ]; then
    NOTE="超时停止采样（${ROUTE_SECONDS}s），已采集 trace"
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
ln -sfn "$RUNTIME_REPORT" "$RUNTIME_REPORT_LATEST"
if [ -n "$APP_PACKAGE" ]; then
echo "dumpsys gfxinfo: $GFXINFO_DIR"
fi

echo "============================================="
echo "运行时采样已结束。已生成 runtime report：$RUNTIME_REPORT"
echo "4) 运行时评分输出："
echo "   - runtime_performance_report: $TRACE_DIR/runtime_performance_latest.md"
echo "   - runtime_performance_json: $TRACE_DIR/runtime_performance_latest.json"

set +e
node ./QA/generate_runtime_performance_report.js "$RUNTIME_REPORT_LATEST"
RUNTIME_SCORE_CODE=$?
set -e
if [ "$RUNTIME_SCORE_CODE" -ne 0 ]; then
  echo "[警告] 自动评分未达标，已输出评分文件（保留缺口供复测）。"
else
  echo "[完成] 运行时评分已生成。"
fi
