#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="${RELEASE_ARTIFACT_DIR:-$ROOT_DIR/artifacts}"
VERSION="${RELEASE_VERSION:-}"
REQUIRE_ANDROID="${REQUIRE_ANDROID_ARTIFACTS:-1}"
REQUIRE_IOS="${REQUIRE_IOS_ARTIFACT:-0}"
REQUIRE_CHECKSUMS="${REQUIRE_CHECKSUM_SIDECARS:-1}"
VERIFY_SIGNATURES="${VERIFY_ARTIFACT_SIGNATURES:-0}"
IOS_BUNDLE_IDENTIFIER="${IOS_BUNDLE_IDENTIFIER:-com.skyapp.personalLedger}"

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
  local structure="$4"
  local sidecar="$path.sha256"
  local size
  local entries

  [[ -f "$path" ]] || fail "Missing $label artifact: $path"
  size="$(stat -f%z "$path" 2>/dev/null || stat -c%s "$path")"
  if (( size < min_bytes )); then
    fail "$label artifact is too small to be a valid release file: $path ($size bytes)"
  fi
  unzip -tq "$path" >/dev/null || fail "$label artifact is not a valid zip container: $path"
  entries="$(unzip -Z1 "$path")"
  check_artifact_structure "$label" "$structure" "$entries"
  if [[ "$VERIFY_SIGNATURES" == "1" ]]; then
    verify_artifact_signature "$label" "$path" "$structure"
    echo "$label signature checks passed."
  fi

  if [[ "$REQUIRE_CHECKSUMS" == "1" && ! -f "$sidecar" ]]; then
    fail "Missing $label checksum sidecar: $sidecar"
  fi

  if [[ -f "$sidecar" ]]; then
    (
      cd "$(dirname "$path")"
      shasum -a 256 -c "$(basename "$sidecar")" >/dev/null
    ) || fail "$label checksum sidecar does not match: $sidecar"
  fi

  printf '%s\t%s bytes\t%s\n' "$(shasum -a 256 "$path" | awk '{print $1}')" "$size" "$path"
}

require_zip_entry() {
  local label="$1"
  local entries="$2"
  local pattern="$3"
  local description="$4"

  if ! grep -Eq "$pattern" <<<"$entries"; then
    fail "$label artifact is missing required $description entry matching: $pattern"
  fi
}

check_artifact_structure() {
  local label="$1"
  local structure="$2"
  local entries="$3"

  case "$structure" in
    apk)
      require_zip_entry "$label" "$entries" '^AndroidManifest\.xml$' 'Android manifest'
      require_zip_entry "$label" "$entries" '^classes([0-9]+)?\.dex$' 'DEX bytecode'
      ;;
    aab)
      require_zip_entry "$label" "$entries" '^BundleConfig\.pb$' 'bundle config'
      require_zip_entry "$label" "$entries" '^base/manifest/AndroidManifest\.xml$' 'base Android manifest'
      require_zip_entry "$label" "$entries" '^base/dex/classes([0-9]+)?\.dex$' 'base DEX bytecode'
      ;;
    ipa)
      require_zip_entry "$label" "$entries" '^Payload/[^/]+\.app/Info\.plist$' 'app Info.plist'
      ;;
    *)
      fail "Unknown artifact structure for $label: $structure"
      ;;
  esac
}

find_apksigner() {
  if command -v apksigner >/dev/null 2>&1; then
    command -v apksigner
    return
  fi

  local sdk_roots=()
  if [[ -n "${ANDROID_HOME:-}" ]]; then
    sdk_roots+=("$ANDROID_HOME")
  fi
  if [[ -n "${ANDROID_SDK_ROOT:-}" && "${ANDROID_SDK_ROOT:-}" != "${ANDROID_HOME:-}" ]]; then
    sdk_roots+=("$ANDROID_SDK_ROOT")
  fi
  sdk_roots+=(
    "$HOME/Library/Android/sdk"
    "/usr/local/lib/android/sdk"
    "/opt/android-sdk"
  )

  local sdk_root
  for sdk_root in "${sdk_roots[@]}"; do
    if [[ -d "$sdk_root/build-tools" ]]; then
      find "$sdk_root/build-tools" -type f -name apksigner | sort -V | tail -n 1
      return
    fi
  done
}

verify_ios_ipa_signature() {
  local label="$1"
  local path="$2"
  local work_dir
  local app_path
  local bundle_id

  require_tool codesign
  work_dir="$(mktemp -d)"
  cleanup_ios_verify() {
    rm -rf "$work_dir"
  }
  trap cleanup_ios_verify EXIT

  unzip -q "$path" -d "$work_dir"
  app_path="$(find "$work_dir/Payload" -maxdepth 1 -type d -name '*.app' -print -quit 2>/dev/null || true)"
  [[ -n "$app_path" ]] || fail "$label artifact does not contain an app bundle under Payload: $path"
  [[ -f "$app_path/Info.plist" ]] || fail "$label artifact app bundle is missing Info.plist: $path"

  bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Info.plist")"
  if [[ "$bundle_id" != "$IOS_BUNDLE_IDENTIFIER" ]]; then
    fail "$label artifact bundle id mismatch: expected $IOS_BUNDLE_IDENTIFIER, got $bundle_id"
  fi

  codesign --verify --deep --strict --verbose=2 "$app_path" >/dev/null
}

verify_artifact_signature() {
  local label="$1"
  local path="$2"
  local structure="$3"
  local apksigner

  case "$structure" in
    apk)
      apksigner="$(find_apksigner)"
      [[ -n "$apksigner" ]] || fail "Missing required tool: apksigner"
      "$apksigner" verify --verbose --print-certs "$path" >/dev/null
      ;;
    aab)
      require_tool jarsigner
      jarsigner -verify -strict -certs "$path" >/dev/null
      ;;
    ipa)
      verify_ios_ipa_signature "$label" "$path"
      ;;
    *)
      fail "Unknown artifact structure for $label: $structure"
      ;;
  esac
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
  check_zip_artifact "Android APK" "$apk_path" 1024000 apk
  check_zip_artifact "Android AAB" "$aab_path" 1024000 aab
fi

if [[ "$REQUIRE_IOS" == "1" ]]; then
  ipa_path="$(find_one "$ipa_pattern")" || fail "Missing iOS IPA artifact matching $ipa_pattern under $ARTIFACT_DIR"
  check_zip_artifact "iOS IPA" "$ipa_path" 1024000 ipa
fi

if [[ "$REQUIRE_ANDROID" != "1" && "$REQUIRE_IOS" != "1" ]]; then
  fail "No artifact requirement enabled. Set REQUIRE_ANDROID_ARTIFACTS=1 and/or REQUIRE_IOS_ARTIFACT=1."
fi

echo "Release artifact file checks passed."
