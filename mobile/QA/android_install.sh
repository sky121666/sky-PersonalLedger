#!/usr/bin/env bash

set -euo pipefail

FLUTTER_BIN="${FLUTTER_BIN:-/private/tmp/sky-personalledger-flutter-sdk/flutter/bin/flutter}"
ADB_BIN="${ADB_BIN:-adb}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MOBILE_DIR="$PROJECT_ROOT"
EMULATOR_BIN="${EMULATOR_BIN:-/opt/homebrew/share/android-commandlinetools/emulator/emulator}"
ANDROID_PREFER_EMULATOR="${ANDROID_PREFER_EMULATOR:-1}"
EMULATOR_WAIT_SECONDS="${EMULATOR_WAIT_SECONDS:-300}"
LEDGER_E2E_LOCAL_SERVER_URL="${LEDGER_E2E_LOCAL_SERVER_URL:-${LEDGER_E2E_SERVER_URL:-}}"
LEDGER_E2E_SERVER_URL="${LEDGER_E2E_SERVER_URL:-}"
LEDGER_E2E_PASSWORD="${LEDGER_E2E_PASSWORD:-}"
LEDGER_E2E_AUTO_AUTH="${LEDGER_E2E_AUTO_AUTH:-}"

detect_current_local_server_url() {
  local candidate
  for candidate in http://127.0.0.1:8080 http://localhost:8080; do
    if curl -fsS "$candidate/api/v1/auth/status" >/dev/null 2>&1; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

server_url_for_device() {
  local local_url="$1"

  if [ -z "$local_url" ]; then
    return 0
  fi

  case "$SELECTED_DEVICE" in
    emulator-*)
      case "$local_url" in
        http://127.0.0.1:*) echo "http://10.0.2.2:${local_url#http://127.0.0.1:}" ;;
        http://localhost:*) echo "http://10.0.2.2:${local_url#http://localhost:}" ;;
        http://127.0.0.1) echo "http://10.0.2.2" ;;
        http://localhost) echo "http://10.0.2.2" ;;
        *) echo "$local_url" ;;
      esac
      ;;
    *)
      echo "$local_url"
      ;;
  esac
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

wait_for_device_online() {
  local target_device="$1"
  local waited=0
  while [ "$waited" -lt "$EMULATOR_WAIT_SECONDS" ]; do
    local raw_devices
    raw_devices="$($ADB_BIN devices -l | awk 'NR>1')"

    if [ -n "$target_device" ]; then
      if printf '%s\n' "$raw_devices" | awk -v device="$target_device" '$1 == device && $2 == "device" {found=1} END {exit !found}'; then
        return 0
      fi
    elif [ "$ANDROID_PREFER_EMULATOR" = "1" ]; then
      if printf '%s\n' "$raw_devices" | awk '$1 ~ /^emulator-/ && $2 == "device" {found=1} END {exit !found}'; then
        return 0
      fi
    else
      if printf '%s\n' "$raw_devices" | awk '$2 == "device" {found=1} END {exit !found}'; then
        return 0
      fi
    fi

    sleep 1
    waited=$((waited + 1))
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
  done

  return 1
}

require_emulator_device() {
  local device="$1"
  if [ "$ANDROID_PREFER_EMULATOR" != "1" ]; then
    return 0
  fi

  case "$device" in
    emulator-*) return 0 ;;
  esac

  echo "[错误] Android QA 当前只接受模拟器目标，收到: $device"
  echo "请启动 Android Emulator，并确认 adb devices -l 中出现 emulator-*。"
  echo "如需临时验证真实设备，请显式设置 ANDROID_PREFER_EMULATOR=0。"
  exit 4
}

list_online_android_targets() {
  if [ "$ANDROID_PREFER_EMULATOR" = "1" ]; then
    "$ADB_BIN" devices -l | awk 'NR>1 && $1 ~ /^emulator-/ && $2 == "device" {print $1}'
  else
    "$ADB_BIN" devices -l | awk 'NR>1 && $2 == "device" {print $1}'
  fi
}

ensure_emulator_started() {
  if [ "$ANDROID_PREFER_EMULATOR" != "1" ]; then
    return 0
  fi

  local emulator_bin
  if ! emulator_bin="$(resolve_emulator_binary)"; then
    echo "[提示] 已开启模拟器优先，但未发现 emulator 可执行路径，不自动启动。"
    return 0
  fi

  local avd_name="${ANDROID_EMULATOR_NAME:-}"
  if [ -z "$avd_name" ]; then
    avd_name="$($emulator_bin -list-avds | awk 'NF>0 {print $1; exit}')"
  fi

  if [ -z "$avd_name" ]; then
    echo "[提示] 未检测到可用 AVD，不自动启动模拟器。"
    return 0
  fi

  if ! printf '%s\n' "$($ADB_BIN devices -l | awk 'NR>1 {print $1}')" | awk '/^emulator-/ {found=1} END {exit !found}'; then
    echo "[信息] 未检测到在线模拟器，尝试启动 $avd_name"
    nohup "$emulator_bin" -avd "$avd_name" -no-snapshot -no-audio -no-boot-anim -gpu swiftshader_indirect >/tmp/qa_emulator_boot.log 2>&1 </dev/null &
    disown "$!" 2>/dev/null || true
  fi
}

if ! command -v "$ADB_BIN" >/dev/null 2>&1; then
  echo "[错误] adb 未安装或未在 PATH。"
  echo "请先在本机安装 Android SDK Platform Tools，并确认 adb 可执行。"
  exit 1
fi

if [ ! -x "$FLUTTER_BIN" ]; then
  if command -v flutter >/dev/null 2>&1; then
    FLUTTER_BIN="$(command -v flutter)"
  else
    echo "[错误] Flutter SDK 未找到。请设置 FLUTTER_BIN 或确保 flutter 在 PATH。"
    exit 1
  fi
fi

DEVICES_RAW="$(list_online_android_targets)"
if [ -z "$DEVICES_RAW" ]; then
  ensure_emulator_started
  sleep 2
  DEVICES_RAW="$(list_online_android_targets)"
fi

if [ -z "$DEVICES_RAW" ]; then
  if [ "${1:-}" != "" ]; then
    echo "[信息] 目标设备 $1 未就绪，等待其上线中（${EMULATOR_WAIT_SECONDS}s）"
  else
    echo "[信息] 未检测到在线设备，等待上线中（${EMULATOR_WAIT_SECONDS}s）"
  fi

  if ! wait_for_device_online "${1:-}"; then
    echo "[错误] 未检测到在线的 Android 模拟器。"
    echo "排查项："
    echo "1) Android Emulator 是否已经启动并完成系统引导"
    echo "2) adb devices -l 是否出现 emulator-* 且状态为 device"
    echo "3) AVD 名称是否正确，可通过 ANDROID_EMULATOR_NAME 指定"
    echo "4) 如由脚本自动启动，检查 /tmp/qa_emulator_boot.log"
    exit 2
  fi

  DEVICES_RAW="$(list_online_android_targets)"
fi

SELECTED_DEVICE="${1:-$(printf '%s\n' "$DEVICES_RAW" | awk 'NR==1 {print $1}')}"
if ! printf '%s\n' "$DEVICES_RAW" | awk -v selected="$SELECTED_DEVICE" '$0 == selected {found=1} END {exit !found}'; then
  echo "[错误] 指定设备不在当前在线列表：$SELECTED_DEVICE"
  echo "可用设备："
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    echo " - $d"
  done <<< "$DEVICES_RAW"
  exit 3
fi
require_emulator_device "$SELECTED_DEVICE"

if ! wait_for_device_services "$SELECTED_DEVICE"; then
  echo "[警告] 设备 $SELECTED_DEVICE 仍未完全就绪（package service 未就绪）。"
  echo "请等 5-10s 后重试，或手动在模拟器上确认启动完成。"
fi

if [ -z "$LEDGER_E2E_LOCAL_SERVER_URL" ]; then
  LEDGER_E2E_LOCAL_SERVER_URL="$(detect_current_local_server_url || true)"
fi
if [ -n "$LEDGER_E2E_LOCAL_SERVER_URL" ]; then
  LEDGER_E2E_SERVER_URL="$(server_url_for_device "$LEDGER_E2E_LOCAL_SERVER_URL")"
fi
if [ -z "$LEDGER_E2E_AUTO_AUTH" ] && [ -n "$LEDGER_E2E_SERVER_URL" ] && [ -n "$LEDGER_E2E_PASSWORD" ]; then
  LEDGER_E2E_AUTO_AUTH="true"
fi

cd "$MOBILE_DIR"
if [ -n "$LEDGER_E2E_SERVER_URL" ]; then
  echo "[信息] 本地账本地址: ${LEDGER_E2E_LOCAL_SERVER_URL:-$LEDGER_E2E_SERVER_URL}"
  if [ "$LEDGER_E2E_SERVER_URL" != "${LEDGER_E2E_LOCAL_SERVER_URL:-$LEDGER_E2E_SERVER_URL}" ]; then
    echo "[信息] 设备访问地址: $LEDGER_E2E_SERVER_URL"
  fi
  BUILD_ARGS=("--debug" "--dart-define" "LEDGER_E2E_SERVER_URL=$LEDGER_E2E_SERVER_URL")
  if [ -n "$LEDGER_E2E_PASSWORD" ]; then
    BUILD_ARGS+=("--dart-define" "LEDGER_E2E_PASSWORD=$LEDGER_E2E_PASSWORD")
    BUILD_ARGS+=("--dart-define" "LEDGER_E2E_AUTO_AUTH=$LEDGER_E2E_AUTO_AUTH")
  fi
  echo "[执行] flutter build apk ${BUILD_ARGS[*]}"
  HOME=/tmp FLUTTER_SUPPRESS_ANALYTICS=true DART_SUPPRESS_ANALYTICS=true "$FLUTTER_BIN" build apk "${BUILD_ARGS[@]}"
  echo "[执行] flutter install -d $SELECTED_DEVICE --use-application-binary build/app/outputs/flutter-apk/app-debug.apk"
  HOME=/tmp FLUTTER_SUPPRESS_ANALYTICS=true DART_SUPPRESS_ANALYTICS=true "$FLUTTER_BIN" install -d "$SELECTED_DEVICE" --debug --use-application-binary build/app/outputs/flutter-apk/app-debug.apk
else
  echo "[执行] flutter install -d $SELECTED_DEVICE"
  HOME=/tmp FLUTTER_SUPPRESS_ANALYTICS=true DART_SUPPRESS_ANALYTICS=true "$FLUTTER_BIN" install -d "$SELECTED_DEVICE"
fi

echo "[完成] 已尝试对设备 $SELECTED_DEVICE 执行安装，若无错误即安装成功。"
