#!/usr/bin/env bash
set -euo pipefail

ADB_BIN="${ADB_BIN:-adb}"
FLUTTER_BIN="${FLUTTER_BIN:-/private/tmp/sky-personalledger-flutter-sdk/flutter/bin/flutter}"
MOBILE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_ROOT="${SKY_LEDGER_TMP_ROOT:-/tmp/sky-personalledger}"
LOG_DIR="$TMP_ROOT/readiness"
ANDROID_PREFER_EMULATOR="${ANDROID_PREFER_EMULATOR:-1}"

if [[ "$ANDROID_PREFER_EMULATOR" != "1" ]]; then
  echo "[策略] Android 读数与运行时采样以模拟器优先执行，当前 ANDROID_PREFER_EMULATOR=${ANDROID_PREFER_EMULATOR} 已被重置为 1。"
  ANDROID_PREFER_EMULATOR="1"
fi
ANDROID_EMULATOR_NAME="${ANDROID_EMULATOR_NAME:-}"
ANDROID_EMULATOR_BOOT_TIMEOUT="${ANDROID_EMULATOR_BOOT_TIMEOUT:-120}"
HOST_HOME="${HOME:-/tmp}"
mkdir -p "$LOG_DIR"

log() { echo "[readiness] $*"; }

log "工作目录: $MOBILE_DIR"

if ! command -v "$ADB_BIN" >/dev/null 2>&1; then
  log "ADB 未在 PATH。请安装 Android Platform Tools。"
  exit 10
fi

resolve_android_sdk_root() {
  local candidates=()
  [[ -n "${ANDROID_SDK_ROOT:-}" ]] && candidates+=("$ANDROID_SDK_ROOT")
  [[ -n "${ANDROID_HOME:-}" ]] && candidates+=("$ANDROID_HOME")
  candidates+=(
    /opt/homebrew/share/android-commandlinetools
    "$HOST_HOME/Library/Android/sdk"
  )
  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate/emulator/emulator" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

wait_emulator_boot() {
  local timeout_seconds="${1:-${ANDROID_EMULATOR_BOOT_TIMEOUT}}"
  local waited=0
  while [ "$waited" -lt "$timeout_seconds" ]; do
    local serial
    serial="$($ADB_BIN devices | awk '$2 == "device" && $1 ~ /^emulator-/{print $1; exit}')"
    if [ -n "$serial" ]; then
      local boot_completed
      boot_completed="$($ADB_BIN -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
      if [ "$boot_completed" = "1" ]; then
        return 0
      fi
    fi
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}

start_android_emulator() {
  if [[ "$ANDROID_PREFER_EMULATOR" != "1" ]]; then
    return 0
  fi

  local sdk_root
  sdk_root="$(resolve_android_sdk_root)" || {
    log "未检测到可用 Android SDK（缺少 emulator），请先设置 ANDROID_SDK_ROOT 并创建 AVD。"
    return 1
  }
  local emulator_bin="$sdk_root/emulator/emulator"
  if [ ! -x "$emulator_bin" ]; then
    log "emulator 不可执行：$emulator_bin"
    return 1
  fi

  local avd_name="${ANDROID_EMULATOR_NAME:-$("$emulator_bin" -list-avds | awk 'NF>0 {print $1; exit}')}"
  if [ -z "$avd_name" ]; then
    log "未检测到可用 AVD。请先创建 Android Emulator AVD，或设置 ANDROID_EMULATOR_NAME。"
    return 1
  fi

  log "未检测到在线模拟器，尝试自动启动: $avd_name"
  "$emulator_bin" -avd "$avd_name" -no-snapshot -no-audio -no-boot-anim -gpu swiftshader_indirect >>"$LOG_DIR/emulator_boot.log" 2>&1 &
  local emulator_pid=$!

  if ! wait_emulator_boot "$ANDROID_EMULATOR_BOOT_TIMEOUT"; then
    log "模拟器未在 ${ANDROID_EMULATOR_BOOT_TIMEOUT}s 内启动完成。"
    log "最近日志如下："
    tail -n 30 "$LOG_DIR/emulator_boot.log" | sed 's/^/[emulator] /' || true
    kill "$emulator_pid" 2>/dev/null || true
    return 1
  fi
  # 由上层流程决定是否保留模拟器
  return 0
}

ensure_emulator_online() {
  if [[ "$ANDROID_PREFER_EMULATOR" != "1" ]]; then
    return 0
  fi
  if "$ADB_BIN" devices | awk '$2 == "device" && $1 ~ /^emulator-/' | grep -q .; then
    return 0
  fi
  if start_android_emulator; then
    sleep 2
    if "$ADB_BIN" devices | awk '$2 == "device" && $1 ~ /^emulator-/' | grep -q .; then
      return 0
    fi
  fi
  return 1
}

if ! command -v "$FLUTTER_BIN" >/dev/null 2>&1; then
  log "flutter 二进制未找到：$FLUTTER_BIN，或请设置 FLUTTER_BIN。"
  exit 11
fi

DEVICE_LIST="$($ADB_BIN devices -l)"
ONLINE_ALL="$(printf '%s\n' "$DEVICE_LIST" | awk 'NR>1 && $2=="device" {print $1}')"
UNAUTHORIZED="$(printf '%s\n' "$DEVICE_LIST" | awk 'NR>1 && ($2=="unauthorized" || $2=="offline") {print $1" "$2}')"

if [ "$ANDROID_PREFER_EMULATOR" = "1" ] && ! ensure_emulator_online; then
  log "模拟器未就绪或无法启动。"
  if [ -n "$ONLINE_ALL" ]; then
    log "当前可见在线模拟器："
    printf '%s\n' "$ONLINE_ALL" | sed 's/^/[device] /'
  fi
  if [ -n "$UNAUTHORIZED" ]; then
    log "当前未授权/离线设备："
    printf '%s\n' "$UNAUTHORIZED" | sed 's/^/[device] /'
  fi
  exit 12
fi

if [ "$ANDROID_PREFER_EMULATOR" = "1" ]; then
  DEVICE_LIST="$($ADB_BIN devices -l)"
  ONLINE_ALL="$(printf '%s\n' "$DEVICE_LIST" | awk 'NR>1 && $2=="device" {print $1}')"
  ONLINE="$(printf '%s\n' "$DEVICE_LIST" | awk 'NR>1 && $2=="device" && $1 ~ /^emulator-/{print $1}')"
else
  ONLINE="$ONLINE_ALL"
fi

if [ -z "$ONLINE" ]; then
  log "未检测到在线设备。"
  if [ "$ANDROID_PREFER_EMULATOR" = "1" ]; then
    if [ -n "$ONLINE_ALL" ]; then
      log "检测到在线设备，但未发现 emulator-*："
      printf '%s\n' "$ONLINE_ALL" | sed 's/^/[device] /'
    else
      log "未检测到可用 Android 模拟器。请先启动 Android Emulator，并确认 adb devices -l 出现 emulator-*。"
    fi
  fi
  if [ -n "$UNAUTHORIZED" ]; then
    log "发现未授权/离线设备："
    printf '%s
' "$UNAUTHORIZED" | sed 's/^/[device] /'
  else
    log "未检测到可用 Android 模拟器。请先启动 Android Emulator，并确认 adb devices -l 出现 emulator-*。"
  fi
  log "如无模拟器可用，请先启动 Android Emulator，并确认 adb devices -l 出现 emulator-*。"
  log "建议执行："
  log "  1) adb kill-server"
  log "  2) adb start-server"
  log "  3) adb devices -l"
  log "  4) 检查并启动 Android Emulator"
  exit 12
fi

COUNT=$(printf '%s\n' "$ONLINE" | sed '/^$/d' | wc -l | tr -d ' ')
log "已连接在线设备数: $COUNT"
printf '%s
' "$ONLINE" | while read -r device; do
  [ -z "$device" ] && continue
  log "设备: $device"
  "$ADB_BIN" -s "$device" shell getprop ro.product.model 2>/dev/null | sed 's/^/  model: /'
  "$ADB_BIN" -s "$device" shell getprop ro.build.version.release 2>/dev/null | sed 's/^/  android: /'
  "$ADB_BIN" -s "$device" shell getprop ro.product.manufacturer 2>/dev/null | sed 's/^/  vendor: /'
  "$ADB_BIN" -s "$device" shell getprop ro.sf.lcd_density 2>/dev/null | sed 's/^/  density: /'
  "$ADB_BIN" -s "$device" shell wm size 2>/dev/null | sed 's/^/  size: /'
  "$ADB_BIN" -s "$device" shell dumpsys power | awk -F: '/mWakefulness/{print "  wakefulness:" $2; exit}'

done

if [ -x "$FLUTTER_BIN" ]; then
  log "开始 Flutter 安装前检查（profile 支持）"
  "$FLUTTER_BIN" --version >/dev/null
  log "Flutter 可用：$FLUTTER_BIN"
fi

log "运行命令建议："
  log "cd $MOBILE_DIR && ANDROID_PREFER_EMULATOR=1 HOME=/private/tmp GRADLE_USER_HOME=$TMP_ROOT/.gradle ANDROID_BUILD_FLAVOR=profile ./QA/android_install.sh"
  log "cd $MOBILE_DIR && ANDROID_PREFER_EMULATOR=1 ./QA/run_android_runtime_gate.sh"

log "预检查完成。"
