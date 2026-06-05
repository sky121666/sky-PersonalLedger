#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APK_PATH="${APK_PATH:-$ROOT_DIR/mobile/build/app/outputs/flutter-apk/app-profile.apk}"
PACKAGE_NAME="${PACKAGE_NAME:-com.skyapp.personal_ledger}"
ANDROID_PREFER_EMULATOR="${ANDROID_PREFER_EMULATOR:-1}"
SERIAL="${ANDROID_SERIAL:-}"
ANDROID_EMULATOR_NAME="${ANDROID_EMULATOR_NAME:-}"
ANDROID_EMULATOR_BOOT_TIMEOUT="${ANDROID_EMULATOR_BOOT_TIMEOUT:-120}"
HOST_HOME="${HOME:-/tmp}"

if [[ "$ANDROID_PREFER_EMULATOR" != "1" ]]; then
  echo "[策略] Android 调试安装以模拟器执行，当前 ANDROID_PREFER_EMULATOR=${ANDROID_PREFER_EMULATOR} 已被重置为 1。"
  ANDROID_PREFER_EMULATOR="1"
fi

fail() {
  echo "$1" >&2
  exit 1
}

pick_emulator_device() {
  adb devices | awk '$2 == "device" && $1 ~ /^emulator-/' | awk 'NR==1 {print $1}'
}

pick_any_device() {
  adb devices | awk '$2 == "device" { print $1; exit }'
}

validate_emulator_only_device() {
  if [[ "$ANDROID_PREFER_EMULATOR" != "1" ]]; then
    return 0
  fi
  if [[ "${1#emulator-}" == "$1" ]]; then
    echo "Expected an Android emulator when ANDROID_PREFER_EMULATOR=1, got: $1" >&2
    echo "Start Android Emulator first and ensure adb devices shows an emulator-* ID." >&2
    return 1
  fi
}

if ! command -v adb >/dev/null 2>&1; then
  fail "adb is required."
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
  local serial
  while [ "$waited" -lt "$timeout_seconds" ]; do
    serial="$(adb devices | awk '$2 == "device" && $1 ~ /^emulator-/{print $1; exit}')"
    if [ -n "$serial" ]; then
      local boot_completed
      boot_completed="$(adb -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
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
    fail "未检测到 Android SDK emulator，请设置 ANDROID_SDK_ROOT 并确认 AVD 已创建。"
  }
  local emulator_bin="$sdk_root/emulator/emulator"
  if [ ! -x "$emulator_bin" ]; then
    fail "emulator 不可执行：$emulator_bin"
  fi

  local avd_name="$ANDROID_EMULATOR_NAME"
  if [ -z "$avd_name" ]; then
    avd_name="$("$emulator_bin" -list-avds | awk 'NF>0 {print $1; exit}')"
  fi
  if [ -z "$avd_name" ]; then
    fail "未找到可用 AVD，请先创建 AVD 或设置 ANDROID_EMULATOR_NAME。"
  fi

  echo "未检测到 emulator，尝试自动启动: $avd_name"
  "$emulator_bin" -avd "$avd_name" -no-snapshot -no-audio -no-boot-anim -gpu swiftshader_indirect >>"/tmp/ledger-profile-emulator.log" 2>&1 &
  if ! wait_emulator_boot "$ANDROID_EMULATOR_BOOT_TIMEOUT"; then
    fail "模拟器启动超时，日志路径: /tmp/ledger-profile-emulator.log"
  fi
}

if [[ ! -f "$APK_PATH" ]]; then
  echo "Profile APK not found: $APK_PATH"
  echo "Building profile APK..."
  (cd "$ROOT_DIR/mobile" && flutter build apk --profile)
fi

if [[ -z "$SERIAL" ]]; then
  if [[ "$ANDROID_PREFER_EMULATOR" == "1" ]]; then
    SERIAL="$(pick_emulator_device)"
    if [ -z "$SERIAL" ]; then
      start_android_emulator
      SERIAL="$(pick_emulator_device)"
    fi
  else
    SERIAL="$(pick_any_device)"
  fi
fi

if [[ "$ANDROID_PREFER_EMULATOR" == "1" ]]; then
  validate_emulator_only_device "$SERIAL" || fail "No Android emulator attached. Start an Android emulator and retry."
fi

[[ -n "$SERIAL" ]] || fail "No Android emulator is connected. Set ANDROID_SERIAL when multiple emulators are attached."

install_args=(-s "$SERIAL" install --no-streaming -r -d "$APK_PATH")

echo "Installing $(basename "$APK_PATH") to $SERIAL with --no-streaming..."
if adb "${install_args[@]}"; then
  echo "Install succeeded."
else
  if [[ "${FORCE_REINSTALL:-0}" == "1" ]]; then
    echo "Install failed; FORCE_REINSTALL=1 set, uninstalling $PACKAGE_NAME and retrying..."
    adb -s "$SERIAL" uninstall "$PACKAGE_NAME" >/dev/null 2>&1 || true
    adb "${install_args[@]}"
    echo "Install succeeded after reinstall."
  else
    cat >&2 <<EOF
Install failed.

If the error is INSTALL_FAILED_UPDATE_INCOMPATIBLE, the emulator already has
with another key. To replace it intentionally, rerun:

  FORCE_REINSTALL=1 ANDROID_SERIAL=$SERIAL $ROOT_DIR/scripts/install-android-profile.sh

FORCE_REINSTALL will uninstall $PACKAGE_NAME first and clear that app's local data.
EOF
    exit 1
  fi
fi

adb -s "$SERIAL" shell monkey -p "$PACKAGE_NAME" -c android.intent.category.LAUNCHER 1 >/dev/null
echo "Launched $PACKAGE_NAME."
