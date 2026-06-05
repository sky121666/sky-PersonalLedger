#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE_LIST_FILE="${DEVICE_LIST_FILE:-}"
ADB_BIN="${ADB_BIN:-adb}"
ANDROID_PREFER_EMULATOR="${ANDROID_PREFER_EMULATOR:-1}"
REQUIRE_ANDROID_EMULATOR="${REQUIRE_ANDROID_EMULATOR:-1}"
ANDROID_EMULATOR_NAME="${ANDROID_EMULATOR_NAME:-}"
ANDROID_EMULATOR_BOOT_TIMEOUT="${ANDROID_EMULATOR_BOOT_TIMEOUT:-120}"
HOST_HOME="${HOME:-/tmp}"

if [[ "$ANDROID_PREFER_EMULATOR" != "1" ]]; then
  echo "[策略] Android QA 以模拟器优先执行，当前 ANDROID_PREFER_EMULATOR=${ANDROID_PREFER_EMULATOR} 已被重置为 1。"
  ANDROID_PREFER_EMULATOR="1"
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter is required" >&2
  exit 1
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
  local elapsed=0
  local serial=""
  local booted=""

  while [ "$elapsed" -lt "$timeout_seconds" ]; do
    serial="$("$ADB_BIN" devices | awk '$2 == "device" && $1 ~ /^emulator-/{print $1; exit}')"
    if [ -n "$serial" ]; then
      booted="$("$ADB_BIN" -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
      if [ "$booted" = "1" ]; then
        echo "$serial"
        return 0
      fi
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 1
}

start_android_emulator() {
  if [[ "$ANDROID_PREFER_EMULATOR" != "1" ]]; then
    return 0
  fi
  if ! command -v "$ADB_BIN" >/dev/null 2>&1; then
    echo "adb is required to launch Android emulator automatically." >&2
    return 1
  fi

  local sdk_root
  sdk_root="$(resolve_android_sdk_root)" || {
    echo "未检测到可用 Android SDK（缺少 emulator），请先启动模拟器或设置 ANDROID_SDK_ROOT。"
    return 1
  }
  local emulator_bin="$sdk_root/emulator/emulator"
  if [ ! -x "$emulator_bin" ]; then
    echo "[错误] emulator 不可执行：$emulator_bin" >&2
    return 1
  fi

  local avd_name
  avd_name="$ANDROID_EMULATOR_NAME"
  if [ -z "$avd_name" ]; then
    avd_name="$("$emulator_bin" -list-avds | awk 'NF>0 {print $1; exit}')"
  fi
  if [ -z "$avd_name" ]; then
    echo "未发现已有 Android Emulator AVD，无法自动启动。"
    echo "请先创建 AVD，或设置 ANDROID_EMULATOR_NAME。"
    return 1
  fi

  echo "[信息] 未检测到在线 emulator，尝试自动启动: $avd_name"
  "$emulator_bin" -avd "$avd_name" -no-snapshot -no-audio -no-boot-anim -gpu swiftshader_indirect >/tmp/ledger_qa_emulator.log 2>&1 &
  local emulator_pid=$!

  if ! wait_emulator_boot "$ANDROID_EMULATOR_BOOT_TIMEOUT" >/tmp/ledger_qa_emulator_boot.txt; then
    echo "[错误] 模拟器未在 ${ANDROID_EMULATOR_BOOT_TIMEOUT}s 内启动完成。" >&2
    echo "[提示] 最近日志："
    tail -n 30 /tmp/ledger_qa_emulator.log | sed 's/^/[emulator] /' || true
    kill "$emulator_pid" 2>/dev/null || true
    return 1
  fi
  # 由上层会话自行管理 emulator 生命周期
  return 0
}

ensure_android_emulator() {
  if [[ "$ANDROID_PREFER_EMULATOR" != "1" ]]; then
    return 0
  fi

  if command -v "$ADB_BIN" >/dev/null 2>&1; then
    if "$ADB_BIN" devices | awk '$2 == "device" && $1 ~ /^emulator-/' | grep -q .; then
      return 0
    fi
  fi

  if ! start_android_emulator; then
    return 1
  fi

  # 给系统一点时间刷新设备列表
  sleep 2
  if [[ "$ANDROID_PREFER_EMULATOR" == "1" ]]; then
    if "$ADB_BIN" devices | awk '$2 == "device" && $1 ~ /^emulator-/' | grep -q .; then
      return 0
    fi
  fi
  return 1
}

if [[ -z "$DEVICE_LIST_FILE" ]]; then
  DEVICE_LIST_FILE="$(mktemp)"
  trap 'rm -f "$DEVICE_LIST_FILE"' EXIT
  flutter devices >"$DEVICE_LIST_FILE"
elif [[ ! -f "$DEVICE_LIST_FILE" ]]; then
  echo "DEVICE_LIST_FILE does not exist: $DEVICE_LIST_FILE" >&2
  exit 1
fi

cat "$DEVICE_LIST_FILE"

has_ios_simulator=0
has_wired_ios_physical=0
has_wireless_ios_physical=0
has_android_emulator=0

if grep -E '• ios[[:space:]]+• .*simulator' "$DEVICE_LIST_FILE" >/dev/null; then
  has_ios_simulator=1
fi

if awk '/android/{ if ($0 ~ /emulator/ || $0 ~ /emulator-/) { found=1; exit } } END { exit (found ? 0 : 1) }' "$DEVICE_LIST_FILE"; then
  has_android_emulator=1
fi

if [[ "$has_android_emulator" != "1" ]]; then
  if [[ "${ANDROID_PREFER_EMULATOR}" == "1" ]]; then
    if ensure_android_emulator; then
      has_android_emulator=1
    fi
  fi
fi

if [[ "$has_android_emulator" != "1" ]] && command -v adb >/dev/null 2>&1; then
  if adb devices | awk '$2 == "device" && $1 ~ /^emulator-/' | grep -q .; then
    has_android_emulator=1
  fi
fi

if grep -E '\(wireless\).*• ios • iOS ' "$DEVICE_LIST_FILE" >/dev/null; then
  has_wireless_ios_physical=1
fi

if grep -E '• ios • iOS ' "$DEVICE_LIST_FILE" | grep -v '\(wireless\)' >/dev/null; then
  has_wired_ios_physical=1
fi

if [[ "${REQUIRE_IOS_SIMULATOR:-0}" == "1" && "$has_ios_simulator" != "1" ]]; then
  echo "No iOS simulator detected." >&2
  exit 1
fi

if [[ "$REQUIRE_ANDROID_EMULATOR" == "1" && "$has_android_emulator" != "1" ]]; then
  echo "No Android emulator detected." >&2
  echo "Start an Android emulator and rerun with REQUIRE_ANDROID_EMULATOR=1." >&2
  exit 1
fi

if [[ "${REQUIRE_PHYSICAL_IOS:-0}" == "1" && "$has_wired_ios_physical" != "1" ]]; then
  if [[ "$has_wireless_ios_physical" == "1" ]]; then
    echo "A wireless iPhone is visible, but USB-connected iPhone is required for physical Flutter integration tests." >&2
  else
    echo "No USB-connected iPhone detected." >&2
  fi
  echo "Connect iPhone by USB, unlock it, trust this Mac, then rerun with REQUIRE_PHYSICAL_IOS=1." >&2
  exit 1
fi

if [[ "${RUN_PHYSICAL_IOS_E2E:-0}" == "1" ]]; then
  if [[ -z "${IOS_PHYSICAL_DEVICE_ID:-}" ]]; then
    echo "IOS_PHYSICAL_DEVICE_ID is required when RUN_PHYSICAL_IOS_E2E=1." >&2
    exit 1
  fi
  if [[ "$has_wired_ios_physical" != "1" ]]; then
    echo "RUN_PHYSICAL_IOS_E2E=1 requires a USB-connected iPhone." >&2
    exit 1
  fi
  (
    cd "$ROOT_DIR"
    RUN_FLUTTER_TESTER_E2E=0 \
      RUN_ANDROID_E2E=0 \
      RUN_IOS_E2E=1 \
      IOS_DEVICE_ID="$IOS_PHYSICAL_DEVICE_ID" \
      ./scripts/verify-mobile-e2e.sh
  )
fi

if [[ "${RUN_ANDROID_E2E:-0}" == "1" ]]; then
  (
    cd "$ROOT_DIR"
    RUN_FLUTTER_TESTER_E2E=0 \
      RUN_ANDROID_E2E=1 \
      RUN_IOS_E2E=0 \
      ANDROID_PREFER_EMULATOR=1 \
      ./scripts/verify-mobile-e2e.sh
  )
fi

echo "Mobile device QA preflight checks passed."
if [[ "$REQUIRE_ANDROID_EMULATOR" == "1" && "$ANDROID_PREFER_EMULATOR" != "1" ]]; then
  echo "Android release/QA path requires emulator now. Keep ANDROID_PREFER_EMULATOR=1." >&2
  exit 1
fi
