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
ANDROID_EXPECTED_SIGNER_SHA256="${ANDROID_EXPECTED_SIGNER_SHA256:-}"
IOS_EXPECTED_TEAM_IDENTIFIER="${IOS_EXPECTED_TEAM_IDENTIFIER:-}"
ANDROID_APK_SIGNER_SHA256=""
ANDROID_AAB_SIGNER_SHA256=""

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
    check_checksum_sidecar "$label" "$path" "$sidecar"
    (
      cd "$(dirname "$path")"
      shasum -a 256 -c "$(basename "$sidecar")" >/dev/null
    ) || fail "$label checksum sidecar does not match: $sidecar"
  fi

  printf '%s\t%s bytes\t%s\n' "$(shasum -a 256 "$path" | awk '{print $1}')" "$size" "$path"
}

check_checksum_sidecar() {
  local label="$1"
  local path="$2"
  local sidecar="$3"
  local expected_name
  local line_count
  local digest
  local filename
  local extra

  expected_name="$(basename "$path")"
  line_count="$(awk 'END { print NR + 0 }' "$sidecar")"
  if [[ "$line_count" != "1" ]]; then
    fail "$label checksum sidecar must contain exactly one checksum line: $sidecar"
  fi

  read -r digest filename extra <"$sidecar"
  if [[ -n "${extra:-}" ]]; then
    fail "$label checksum sidecar must contain only digest and filename: $sidecar"
  fi
  if [[ ! "$digest" =~ ^[0-9a-fA-F]{64}$ ]]; then
    fail "$label checksum sidecar digest is not a SHA-256 hex value: $sidecar"
  fi
  if [[ "$filename" != "$expected_name" ]]; then
    fail "$label checksum sidecar filename mismatch: expected $expected_name, got ${filename:-<empty>}"
  fi
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
      find "$sdk_root/build-tools" -type f -name apksigner -print
    fi
  done |
    awk '
      function version_key(path, parts, count, key, i) {
        count = split(path, parts, "/")
        key = parts[count - 1]
        gsub(/[^0-9.]/, ".", key)
        count = split(key, parts, ".")
        key = ""
        for (i = 1; i <= 4; i++) {
          key = key sprintf("%08d", parts[i] + 0)
        }
        return key
      }
      {
        key = version_key($0)
        if (key >= best_key) {
          best_key = key
          best_path = $0
        }
      }
      END {
        if (best_path != "") print best_path
      }
    '
}

verify_ios_ipa_signature() {
  local label="$1"
  local path="$2"
  local work_dir
  local app_path
  local bundle_id
  local entitlements_path
  local team_identifier
  local application_identifier

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

  if [[ ! "$IOS_EXPECTED_TEAM_IDENTIFIER" =~ ^[A-Z0-9]{10}$ ]]; then
    fail "IOS_EXPECTED_TEAM_IDENTIFIER must be set to the protected 10-character Team ID when verifying an IPA"
  fi
  entitlements_path="$work_dir/signing-entitlements.plist"
  codesign -d --entitlements :- "$app_path" >"$entitlements_path" 2>/dev/null
  team_identifier="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.team-identifier' "$entitlements_path")"
  application_identifier="$(/usr/libexec/PlistBuddy -c 'Print :application-identifier' "$entitlements_path")"
  if [[ "$team_identifier" != "$IOS_EXPECTED_TEAM_IDENTIFIER" ]]; then
    fail "$label artifact TeamIdentifier does not match the protected release identity"
  fi
  if [[ "$application_identifier" != "${IOS_EXPECTED_TEAM_IDENTIFIER}.${bundle_id}" ]]; then
    fail "$label artifact application-identifier does not match the expected team and bundle id"
  fi
}

verify_artifact_signature() {
  local label="$1"
  local path="$2"
  local structure="$3"
  local apksigner
  local signer_output
  local expected_signer

  expected_signer="$(printf '%s' "$ANDROID_EXPECTED_SIGNER_SHA256" | tr '[:upper:]' '[:lower:]')"

  case "$structure" in
    apk)
      [[ "$expected_signer" =~ ^[0-9a-f]{64}$ ]] ||
        fail "ANDROID_EXPECTED_SIGNER_SHA256 must be set to the protected 64-hex fingerprint when verifying Android artifacts"
      apksigner="$(find_apksigner)"
      [[ -n "$apksigner" ]] || fail "Missing required tool: apksigner"
      signer_output="$("$apksigner" verify --verbose --print-certs "$path")"
      ANDROID_APK_SIGNER_SHA256="$(awk -F': ' '/Signer #1 certificate SHA-256 digest:/ {print $2; exit}' <<<"$signer_output" |
        tr -d ':' | tr '[:upper:]' '[:lower:]')"
      [[ "$ANDROID_APK_SIGNER_SHA256" == "$expected_signer" ]] ||
        fail "$label signer fingerprint does not match the protected release identity"
      ;;
    aab)
      [[ "$expected_signer" =~ ^[0-9a-f]{64}$ ]] ||
        fail "ANDROID_EXPECTED_SIGNER_SHA256 must be set to the protected 64-hex fingerprint when verifying Android artifacts"
      require_tool jarsigner
      require_tool keytool
      jarsigner -verify -strict -certs "$path" >/dev/null
      ANDROID_AAB_SIGNER_SHA256="$(LC_ALL=C keytool -printcert -jarfile "$path" |
        awk -F': ' '/SHA256:/{print $2; exit}' |
        tr -d ':' | tr '[:upper:]' '[:lower:]')"
      [[ "$ANDROID_AAB_SIGNER_SHA256" == "$expected_signer" ]] ||
        fail "$label signer fingerprint does not match the protected release identity"
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
  if [[ "$VERIFY_SIGNATURES" == "1" && "$ANDROID_APK_SIGNER_SHA256" != "$ANDROID_AAB_SIGNER_SHA256" ]]; then
    fail "Android APK and AAB signer fingerprints do not match"
  fi
fi

if [[ "$REQUIRE_IOS" == "1" ]]; then
  ipa_path="$(find_one "$ipa_pattern")" || fail "Missing iOS IPA artifact matching $ipa_pattern under $ARTIFACT_DIR"
  check_zip_artifact "iOS IPA" "$ipa_path" 1024000 ipa
fi

if [[ "$REQUIRE_ANDROID" != "1" && "$REQUIRE_IOS" != "1" ]]; then
  fail "No artifact requirement enabled. Set REQUIRE_ANDROID_ARTIFACTS=1 and/or REQUIRE_IOS_ARTIFACT=1."
fi

echo "Release artifact file checks passed."
