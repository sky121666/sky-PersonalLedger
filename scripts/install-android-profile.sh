#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APK_PATH="${APK_PATH:-$ROOT_DIR/mobile/build/app/outputs/flutter-apk/app-profile.apk}"
PACKAGE_NAME="${PACKAGE_NAME:-com.skyapp.personal_ledger}"
SERIAL="${ANDROID_SERIAL:-}"

fail() {
  echo "$1" >&2
  exit 1
}

if ! command -v adb >/dev/null 2>&1; then
  fail "adb is required."
fi

if [[ ! -f "$APK_PATH" ]]; then
  echo "Profile APK not found: $APK_PATH"
  echo "Building profile APK..."
  (cd "$ROOT_DIR/mobile" && flutter build apk --profile)
fi

if [[ -z "$SERIAL" ]]; then
  SERIAL="$(adb devices | awk '$2 == "device" { print $1; exit }')"
fi

[[ -n "$SERIAL" ]] || fail "No Android device is connected. Set ANDROID_SERIAL when multiple devices are attached."

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

If the error is INSTALL_FAILED_UPDATE_INCOMPATIBLE, the phone has a build signed
with another key. To replace it intentionally, rerun:

  FORCE_REINSTALL=1 ANDROID_SERIAL=$SERIAL $ROOT_DIR/scripts/install-android-profile.sh

FORCE_REINSTALL will uninstall $PACKAGE_NAME first and clear that app's local data.
EOF
    exit 1
  fi
fi

adb -s "$SERIAL" shell monkey -p "$PACKAGE_NAME" -c android.intent.category.LAUNCHER 1 >/dev/null
echo "Launched $PACKAGE_NAME."
