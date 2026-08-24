#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
backend_pid=""
ANDROID_PREFER_EMULATOR="${ANDROID_PREFER_EMULATOR:-1}"
ANDROID_EMULATOR_BOOT_TIMEOUT="${ANDROID_EMULATOR_BOOT_TIMEOUT:-300}"
android_emulator_pid=""
android_avd_name=""
booted_ios_device=""
android_device=""
ios_device=""
android_local_properties=""
android_local_properties_backup=""
android_local_properties_existed=0

if [[ "$ANDROID_PREFER_EMULATOR" != "1" ]]; then
  echo "[策略] Android E2E 一律走模拟器，当前 ANDROID_PREFER_EMULATOR=${ANDROID_PREFER_EMULATOR} 已被重置为 1。"
  ANDROID_PREFER_EMULATOR="1"
fi

cleanup() {
  if [[ -n "$backend_pid" ]] && kill -0 "$backend_pid" 2>/dev/null; then
    kill "$backend_pid" 2>/dev/null || true
    wait "$backend_pid" 2>/dev/null || true
  fi
  if [[ -n "$android_emulator_pid" ]] && kill -0 "$android_emulator_pid" 2>/dev/null; then
    kill "$android_emulator_pid" 2>/dev/null || true
    wait "$android_emulator_pid" 2>/dev/null || true
  fi
  if [[ -n "$android_avd_name" && -x "${AVDMANAGER:-}" ]]; then
    "$AVDMANAGER" delete avd -n "$android_avd_name" >/dev/null 2>&1 || true
  fi
  if [[ -n "$booted_ios_device" ]]; then
    xcrun simctl shutdown "$booted_ios_device" >/dev/null 2>&1 || true
  fi
  if [[ -n "$android_local_properties" ]]; then
    if [[ "$android_local_properties_existed" == "1" && -f "$android_local_properties_backup" ]]; then
      cp "$android_local_properties_backup" "$android_local_properties" 2>/dev/null || true
    else
      rm -f "$android_local_properties" 2>/dev/null || true
    fi
  fi
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

if ! command -v go >/dev/null 2>&1; then
  echo "go is required" >&2
  exit 1
fi
if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter is required" >&2
  exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required" >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required" >&2
  exit 1
fi

pick_port() {
  python3 - <<'PY'
import socket

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
}

wait_for_backend() {
  local status_url="$1"
  for _ in $(seq 1 80); do
    if curl -fsS "$status_url" >/dev/null 2>&1; then
      return 0
    fi
    if ! kill -0 "$backend_pid" 2>/dev/null; then
      echo "backend exited before becoming ready" >&2
      sed -n '1,220p' "$tmp_dir/backend.log" >&2 || true
      return 1
    fi
    sleep 0.25
  done

  echo "backend did not become ready: $status_url" >&2
  sed -n '1,220p' "$tmp_dir/backend.log" >&2 || true
  return 1
}

terminate_process_tree() {
  local pid="$1"
  local child

  for child in $(pgrep -P "$pid" 2>/dev/null || true); do
    terminate_process_tree "$child"
  done

  kill "$pid" 2>/dev/null || true
}

dump_android_diagnostics() {
  echo "Android diagnostics:" >&2
  if command -v adb >/dev/null 2>&1; then
    adb devices >&2 || true
  fi

  ps ax -o pid,ppid,etime,%cpu,%mem,stat,command \
    | grep -E 'flutter|gradle|GradleDaemon|kotlin|adb|emulator' \
    | grep -v grep >&2 || true

  if [[ -n "${GRADLE_USER_HOME:-}" && -d "$GRADLE_USER_HOME" ]]; then
    local log_file
    while IFS= read -r log_file; do
      echo "Gradle daemon log tail: $log_file" >&2
      tail -120 "$log_file" >&2 || true
    done < <(find "$GRADLE_USER_HOME" -path '*/daemon/*/*.out.log' -type f 2>/dev/null | sort | tail -3)
  fi

  if [[ -n "$android_emulator_pid" && -f "$tmp_dir/android-emulator.log" ]]; then
    echo "Android emulator log tail:" >&2
    tail -120 "$tmp_dir/android-emulator.log" >&2 || true
  fi
}

run_with_timeout() {
  local timeout_seconds="$1"
  shift

  "$@" &
  local command_pid="$!"
  local started_at now elapsed
  started_at="$(date +%s)"

  while kill -0 "$command_pid" 2>/dev/null; do
    now="$(date +%s)"
    elapsed=$((now - started_at))
    if (( elapsed >= timeout_seconds )); then
      echo "Command timed out after ${timeout_seconds}s: $*" >&2
      if [[ "${RUN_ANDROID_E2E:-0}" == "1" ]]; then
        dump_android_diagnostics
      fi
      terminate_process_tree "$command_pid"
      wait "$command_pid" 2>/dev/null || true
      return 124
    fi
    sleep 2
  done

  wait "$command_pid"
}

run_flutter_e2e() {
  local device_id="$1"
  local server_url="$2"
  local storage_mode="$3"
  local test_file="${LEDGER_MOBILE_E2E_TEST_FILE:-integration_test/app_real_backend_e2e_test.dart}"

  (
    cd "$repo_root/mobile"
    run_with_timeout "$LEDGER_MOBILE_E2E_TIMEOUT_SECONDS" \
      flutter test \
      -d "$device_id" \
      --timeout="${LEDGER_MOBILE_E2E_TEST_TIMEOUT:-${LEDGER_MOBILE_E2E_TIMEOUT_SECONDS}s}" \
      --dart-define="LEDGER_E2E_SERVER_URL=$server_url" \
      --dart-define="LEDGER_E2E_PASSWORD=$LEDGER_E2E_PASSWORD" \
      --dart-define="LEDGER_E2E_AUTO_AUTH=true" \
      --dart-define="LEDGER_E2E_USE_IN_MEMORY_STORAGE=$storage_mode" \
      --dart-define="LEDGER_E2E_TEST_TIMEOUT_SECONDS=$LEDGER_MOBILE_E2E_TIMEOUT_SECONDS" \
      "$test_file"
  )
}

resolve_android_sdk_root() {
  local candidates=()
  [[ -n "${ANDROID_SDK_ROOT:-}" ]] && candidates+=("$ANDROID_SDK_ROOT")
  [[ -n "${ANDROID_HOME:-}" ]] && candidates+=("$ANDROID_HOME")
  candidates+=(
    /opt/homebrew/share/android-commandlinetools
    "$HOME/Library/Android/sdk"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate/platform-tools/adb" \
      && -x "$candidate/emulator/emulator" \
      && -x "$candidate/cmdline-tools/latest/bin/avdmanager" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

configure_android_environment() {
  local sdk_root
  sdk_root="$(resolve_android_sdk_root)" || {
    echo "Android SDK not found. Set ANDROID_SDK_ROOT to a complete SDK before RUN_ANDROID_E2E=1." >&2
    return 1
  }

  export ANDROID_SDK_ROOT="$sdk_root"
  export ANDROID_HOME="$sdk_root"
  export ANDROID_USER_HOME="${ANDROID_E2E_USER_HOME:-$tmp_dir/android-user-home}"
  export ANDROID_AVD_HOME="${ANDROID_E2E_AVD_HOME:-$ANDROID_USER_HOME/avd}"
  local default_gradle_home="$repo_root/mobile/.gradle"
  export GRADLE_USER_HOME="${GRADLE_E2E_USER_HOME:-$default_gradle_home}"
  mkdir -p "$ANDROID_USER_HOME" "$ANDROID_AVD_HOME" "$GRADLE_USER_HOME"
  cat >"$GRADLE_USER_HOME/gradle.properties" <<'EOF'
org.gradle.daemon=false
org.gradle.caching=false
org.gradle.parallel=false
kotlin.compiler.execution.strategy=in-process
EOF

  export PATH="$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/emulator:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$PATH"
  AVDMANAGER="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/avdmanager"

  android_local_properties="$repo_root/mobile/android/local.properties"
  android_local_properties_backup="$tmp_dir/android-local.properties.bak"
  if [[ -f "$android_local_properties" ]]; then
    android_local_properties_existed=1
    cp "$android_local_properties" "$android_local_properties_backup"
  fi

  local flutter_bin flutter_sdk
  flutter_bin="$(command -v flutter)"
  local flutter_link_target
  flutter_link_target="$(readlink "$flutter_bin" || true)"
  if [[ -n "$flutter_link_target" ]]; then
    if [[ "$flutter_link_target" != /* ]]; then
      flutter_link_target="$(cd "$(dirname "$flutter_bin")" && cd "$(dirname "$flutter_link_target")" && pwd -P)/$(basename "$flutter_link_target")"
    fi
    flutter_bin="$flutter_link_target"
  fi
  flutter_sdk="$(cd "$(dirname "$flutter_bin")/.." && pwd -P)"
  {
    printf 'sdk.dir=%s\n' "$ANDROID_SDK_ROOT"
    printf 'flutter.sdk=%s\n' "$flutter_sdk"
  } >"$android_local_properties"
}

resolve_android_device() {
  if [[ -n "${ANDROID_SERIAL:-}" ]]; then
    if [[ "${ANDROID_PREFER_EMULATOR}" == "1" ]]; then
      if [[ "${ANDROID_SERIAL}" == emulator-* ]]; then
        android_device="$ANDROID_SERIAL"
        return 0
      fi

      echo "ANDROID_PREFER_EMULATOR=1, ANDROID_SERIAL is not an emulator: ${ANDROID_SERIAL}" >&2
      echo "Ignore the explicit device and try to use an online emulator first." >&2
      local running_serial
      running_serial="$(adb devices | awk '$2 == "device" && $1 ~ /^emulator-/ { print $1; exit }')"
      if [[ -n "$running_serial" ]]; then
        android_device="$running_serial"
        return 0
      fi
      echo "No online emulator found yet, will start one automatically." >&2
    else
      android_device="$ANDROID_SERIAL"
      return 0
    fi
  fi

  local running
  running="$(adb devices | awk '$2 == "device" && $1 ~ /^emulator-/ { print $1; exit }')"
  if [[ -n "$running" ]]; then
    android_device="$running"
    return 0
  fi

  local emulator_bin="$ANDROID_SDK_ROOT/emulator/emulator"
  if [[ ! -x "$AVDMANAGER" || ! -x "$emulator_bin" ]]; then
    echo "Android avdmanager/emulator not found under $ANDROID_SDK_ROOT." >&2
    return 1
  fi

  local system_image="${ANDROID_E2E_SYSTEM_IMAGE:-system-images;android-35;google_apis;arm64-v8a}"
  android_avd_name="ledger_e2e_$$"
  printf 'no\n' | "$AVDMANAGER" create avd \
    -n "$android_avd_name" \
    -k "$system_image" \
    -d pixel_6 >/dev/null

  "$emulator_bin" -avd "$android_avd_name" \
    -no-snapshot \
    -no-audio \
    -no-metrics \
    -no-window \
    -no-boot-anim \
    -gpu swiftshader_indirect \
    >"$tmp_dir/android-emulator.log" 2>&1 &
  android_emulator_pid="$!"

  local device
  for _ in $(seq 1 "$ANDROID_EMULATOR_BOOT_TIMEOUT"); do
    device="$(adb devices | awk '$2 == "device" && $1 ~ /^emulator-/ { print $1; exit }')"
    if [[ -n "$device" ]]; then
      local boot_completed
      boot_completed="$(adb -s "$device" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
      if [[ "$boot_completed" == "1" ]]; then
        android_device="$device"
        return 0
      fi
    fi
    sleep 1
  done

  echo "Android emulator did not boot in time" >&2
  sed -n '1,220p' "$tmp_dir/android-emulator.log" >&2 || true
  return 1
}

resolve_ios_device() {
  if [[ -n "${IOS_DEVICE_ID:-}" ]]; then
    ios_device="$IOS_DEVICE_ID"
    return 0
  fi

  local selected
  selected="$(xcrun simctl list devices available -j | python3 -c '
import json
import re
import sys

data = json.load(sys.stdin)

def runtime_version(runtime):
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not match:
        return (0, 0)
    return tuple(int(part) for part in match.groups())

candidates = []
for runtime, devices in data.get("devices", {}).items():
    if "iOS" not in runtime:
        continue
    for device in devices:
        if not device.get("isAvailable", True):
            continue
        name = device.get("name", "")
        if name == "iPhone 17":
            priority = 0
        elif name.startswith("iPhone"):
            priority = 1
        else:
            continue
        version = runtime_version(runtime)
        candidates.append((priority, -version[0], -version[1], name, device.get("udid", ""), device.get("state", "")))

candidates.sort()
if candidates:
    _, _, _, name, udid, state = candidates[0]
    print(f"{udid}\t{state}\t{name}")
')" || {
    echo "No available iPhone simulator found." >&2
    return 1
  }

  if [[ -z "$selected" ]]; then
    echo "No available iPhone simulator found." >&2
    return 1
  fi

  local device state device_name
  IFS=$'\t' read -r device state device_name <<<"$selected"
  if [[ "$state" != "Booted" ]]; then
    xcrun simctl boot "$device"
    booted_ios_device="$device"
  fi
  xcrun simctl bootstatus "$device" -b >/dev/null
  ios_device="$device"
}

LEDGER_E2E_PASSWORD="${LEDGER_E2E_PASSWORD:-LedgerE2ePass123!}"
LEDGER_MOBILE_E2E_TIMEOUT_SECONDS="${LEDGER_MOBILE_E2E_TIMEOUT_SECONDS:-900}"
RUN_FLUTTER_TESTER_E2E="${RUN_FLUTTER_TESTER_E2E:-1}"
RUN_ANDROID_E2E="${RUN_ANDROID_E2E:-0}"
RUN_IOS_E2E="${RUN_IOS_E2E:-0}"

if [[ "$RUN_FLUTTER_TESTER_E2E" != "1" && "$RUN_ANDROID_E2E" != "1" && "$RUN_IOS_E2E" != "1" ]]; then
  echo "No mobile E2E target enabled. Enable RUN_FLUTTER_TESTER_E2E, RUN_ANDROID_E2E, or RUN_IOS_E2E." >&2
  exit 1
fi

backend_port="${LEDGER_E2E_BACKEND_PORT:-$(pick_port)}"
backend_base_url="http://127.0.0.1:$backend_port"
backend_binary="$tmp_dir/ledger-server"
mkdir -p "$tmp_dir/uploads" "$tmp_dir/backups" "$tmp_dir/web"

echo "Mobile E2E targets: flutter-tester=$RUN_FLUTTER_TESTER_E2E android=$RUN_ANDROID_E2E ios=$RUN_IOS_E2E"
echo "Building isolated backend before starting the readiness timeout..."
(
  cd "$repo_root/backend"
  go build -o "$backend_binary" ./cmd/server
)
echo "Starting isolated SQLite backend at $backend_base_url"

(
  LEDGER_SERVER_PORT="$backend_port" \
  LEDGER_SERVER_MODE=debug \
  LEDGER_SERVER_WEB_PATH="$tmp_dir/web" \
  LEDGER_DATABASE_DRIVER=sqlite \
  LEDGER_DATABASE_PATH="$tmp_dir/ledger.db" \
  LEDGER_SETUP_CONFIG_PATH="$tmp_dir/config.yaml" \
  LEDGER_JWT_SECRET="${LEDGER_JWT_SECRET:-ledger-e2e-secret-32-characters-minimum}" \
  LEDGER_STORAGE_UPLOAD_PATH="$tmp_dir/uploads" \
  LEDGER_STORAGE_BACKUP_PATH="$tmp_dir/backups" \
  LEDGER_CORS_ALLOWED_ORIGINS='*' \
  "$backend_binary"
) >"$tmp_dir/backend.log" 2>&1 &
backend_pid="$!"

wait_for_backend "$backend_base_url/api/v1/auth/status"

if [[ "$RUN_FLUTTER_TESTER_E2E" == "1" ]]; then
  echo "Running real backend E2E on flutter-tester..."
  run_flutter_e2e flutter-tester "$backend_base_url" true
fi

if [[ "$RUN_ANDROID_E2E" == "1" ]]; then
  configure_android_environment
  resolve_android_device
  echo "Running real backend E2E on Android device $android_device..."
  run_flutter_e2e "$android_device" "http://10.0.2.2:$backend_port" false
fi

if [[ "$RUN_IOS_E2E" == "1" ]]; then
  resolve_ios_device
  echo "Running real backend E2E on iOS simulator $ios_device..."
  run_flutter_e2e "$ios_device" "$backend_base_url" false
fi
