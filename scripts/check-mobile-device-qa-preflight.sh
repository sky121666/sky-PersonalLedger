#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE_LIST_FILE="${DEVICE_LIST_FILE:-}"

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter is required" >&2
  exit 1
fi

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

if grep -E '• ios[[:space:]]+• .*simulator' "$DEVICE_LIST_FILE" >/dev/null; then
  has_ios_simulator=1
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

echo "Mobile device QA preflight checks passed."
