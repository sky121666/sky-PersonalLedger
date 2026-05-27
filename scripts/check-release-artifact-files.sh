#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="${RELEASE_ARTIFACT_DIR:-$ROOT_DIR/artifacts}"
VERSION="${RELEASE_VERSION:-}"
REQUIRE_ANDROID="${REQUIRE_ANDROID_ARTIFACTS:-1}"
REQUIRE_IOS="${REQUIRE_IOS_ARTIFACT:-0}"

fail() {
  echo "$1" >&2
  exit 1
}

require_tool() {
  local name="$1"
  command -v "$name" >/dev/null 2>&1 || fail "Missing required tool: $name"
}

find_one() {
  local pattern="$1"
  local match_count
  match_count="$(find "$ARTIFACT_DIR" -type f -name "$pattern" | wc -l | tr -d ' ')"
  if [[ "$match_count" == "0" ]]; then
    return 1
  fi
  if [[ "$match_count" != "1" ]]; then
    find "$ARTIFACT_DIR" -type f -name "$pattern" >&2
    fail "Expected exactly one artifact matching $pattern, found $match_count"
  fi
  find "$ARTIFACT_DIR" -type f -name "$pattern" -print -quit
}

check_zip_artifact() {
  local label="$1"
  local path="$2"
  local min_bytes="$3"
  local sidecar="$path.sha256"
  local size

  [[ -f "$path" ]] || fail "Missing $label artifact: $path"
  size="$(stat -f%z "$path" 2>/dev/null || stat -c%s "$path")"
  if (( size < min_bytes )); then
    fail "$label artifact is too small to be a valid release file: $path ($size bytes)"
  fi
  unzip -tq "$path" >/dev/null || fail "$label artifact is not a valid zip container: $path"

  if [[ -f "$sidecar" ]]; then
    (
      cd "$(dirname "$path")"
      shasum -a 256 -c "$(basename "$sidecar")" >/dev/null
    ) || fail "$label checksum sidecar does not match: $sidecar"
  fi

  printf '%s\t%s bytes\t%s\n' "$(shasum -a 256 "$path" | awk '{print $1}')" "$size" "$path"
}

require_tool find
require_tool shasum
require_tool unzip

[[ -d "$ARTIFACT_DIR" ]] || fail "Missing artifact directory: $ARTIFACT_DIR"

if [[ -n "$VERSION" ]]; then
  apk_pattern="personal-ledger-$VERSION-android.apk"
  aab_pattern="personal-ledger-$VERSION-android.aab"
  ipa_pattern="personal-ledger-$VERSION-ios.ipa"
else
  apk_pattern="personal-ledger-*-android.apk"
  aab_pattern="personal-ledger-*-android.aab"
  ipa_pattern="personal-ledger-*-ios.ipa"
fi

echo "Release artifact evidence:"

if [[ "$REQUIRE_ANDROID" == "1" ]]; then
  apk_path="$(find_one "$apk_pattern")" || fail "Missing Android APK artifact matching $apk_pattern under $ARTIFACT_DIR"
  aab_path="$(find_one "$aab_pattern")" || fail "Missing Android AAB artifact matching $aab_pattern under $ARTIFACT_DIR"
  check_zip_artifact "Android APK" "$apk_path" 1024000
  check_zip_artifact "Android AAB" "$aab_path" 1024000
fi

if [[ "$REQUIRE_IOS" == "1" ]]; then
  ipa_path="$(find_one "$ipa_pattern")" || fail "Missing iOS IPA artifact matching $ipa_pattern under $ARTIFACT_DIR"
  check_zip_artifact "iOS IPA" "$ipa_path" 1024000
fi

if [[ "$REQUIRE_ANDROID" != "1" && "$REQUIRE_IOS" != "1" ]]; then
  fail "No artifact requirement enabled. Set REQUIRE_ANDROID_ARTIFACTS=1 and/or REQUIRE_IOS_ARTIFACT=1."
fi

echo "Release artifact file checks passed."
