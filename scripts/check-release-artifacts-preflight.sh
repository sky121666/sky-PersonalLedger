#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

require_file() {
  local path="$1"
  if [[ ! -f "$ROOT_DIR/$path" ]]; then
    echo "Missing required file: $path" >&2
    exit 1
  fi
}

require_text() {
  local path="$1"
  local pattern="$2"
  if ! grep -qE "$pattern" "$ROOT_DIR/$path"; then
    echo "Missing required pattern in $path: $pattern" >&2
    exit 1
  fi
}

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required environment variable: $name" >&2
    exit 1
  fi
}

base64_decode_check() {
  local name="$1"
  if ! printf '%s' "${!name}" | base64 --decode >/dev/null 2>&1; then
    echo "Environment variable is not valid base64: $name" >&2
    exit 1
  fi
}

require_file ".github/workflows/android.yml"
require_file ".github/workflows/ios.yml"
require_file ".github/workflows/release.yml"
require_file "docs/android-release-signing.md"
require_file "docs/ios-release-signing.md"
require_file "mobile/android/app/build.gradle.kts"
require_file "mobile/ios/Runner/Info.plist"
require_file "mobile/ios/Runner.xcodeproj/project.pbxproj"

require_text ".github/workflows/android.yml" "ANDROID_KEYSTORE_BASE64"
require_text ".github/workflows/android.yml" "personal-ledger-.*-android\\.apk"
require_text ".github/workflows/android.yml" "personal-ledger-.*-android\\.aab"
require_text ".github/workflows/android.yml" "personal-ledger-.*-android\\.apk\\.sha256"
require_text ".github/workflows/android.yml" "personal-ledger-.*-android\\.aab\\.sha256"
require_text ".github/workflows/android.yml" "Verify Android release signatures"
require_text ".github/workflows/android.yml" "APKSIGNER.*verify --verbose --print-certs"
require_text ".github/workflows/android.yml" "jarsigner -verify -strict -certs"
require_text ".github/workflows/ios.yml" "IOS_CERTIFICATE_BASE64"
require_text ".github/workflows/ios.yml" "workflow_call"
require_text ".github/workflows/ios.yml" "personal-ledger-.*-ios\\.ipa"
require_text ".github/workflows/ios.yml" "personal-ledger-.*-ios\\.ipa\\.sha256"
require_text ".github/workflows/ios.yml" "Verify iOS IPA signature"
require_text ".github/workflows/ios.yml" "CFBundleIdentifier"
require_text ".github/workflows/ios.yml" "codesign --verify --deep --strict"
require_text ".github/workflows/release.yml" "uses: \\.\\/\\.github\\/workflows\\/ios\\.yml"
require_text ".github/workflows/release.yml" "needs: \\[prepare, docker, android, ios\\]"
require_text ".github/workflows/release.yml" "artifacts/android-release/\\*\\.apk"
require_text ".github/workflows/release.yml" "artifacts/android-release/\\*\\.aab"
require_text ".github/workflows/release.yml" "artifacts/android-release/\\*\\.apk\\.sha256"
require_text ".github/workflows/release.yml" "artifacts/android-release/\\*\\.aab\\.sha256"
require_text ".github/workflows/release.yml" "artifacts/ios-ipa/\\*\\.ipa"
require_text ".github/workflows/release.yml" "artifacts/ios-ipa/\\*\\.ipa\\.sha256"
require_text ".github/workflows/release.yml" "check-release-artifact-files\\.sh"
require_text ".github/workflows/release.yml" "REQUIRE_IOS_ARTIFACT=1"
require_text ".github/workflows/release.yml" "VERIFY_ARTIFACT_SIGNATURES=1"
require_text "mobile/android/app/build.gradle.kts" "Debug signing is intentionally disabled for release builds"
require_text "mobile/android/app/build.gradle.kts" "ledgerAllowReleaseCleartext"
require_text "mobile/android/app/src/main/AndroidManifest.xml" 'android:usesCleartextTraffic="\$\{usesCleartextTraffic\}"'
require_text "mobile/ios/Runner.xcodeproj/project.pbxproj" "PRODUCT_BUNDLE_IDENTIFIER = com\\.skyapp\\.personalLedger"
require_text "mobile/ios/Runner.xcodeproj/project.pbxproj" "DEVELOPMENT_TEAM = WV9H55K7S3"

if [[ "${CHECK_SIGNING_SECRETS:-0}" == "1" ]]; then
  for name in ANDROID_KEYSTORE_BASE64 ANDROID_KEYSTORE_PASSWORD ANDROID_KEY_ALIAS ANDROID_KEY_PASSWORD; do
    require_env "$name"
  done
  base64_decode_check "ANDROID_KEYSTORE_BASE64"

  for name in IOS_CERTIFICATE_BASE64 IOS_CERTIFICATE_PASSWORD IOS_PROVISIONING_PROFILE_BASE64 IOS_EXPORT_OPTIONS_PLIST_BASE64 IOS_KEYCHAIN_PASSWORD; do
    require_env "$name"
  done
  base64_decode_check "IOS_CERTIFICATE_BASE64"
  base64_decode_check "IOS_PROVISIONING_PROFILE_BASE64"
  base64_decode_check "IOS_EXPORT_OPTIONS_PLIST_BASE64"
fi

if [[ "${CHECK_LOCAL_ANDROID_SIGNING:-0}" == "1" ]]; then
  require_file "mobile/android/key.properties"
  require_file "mobile/android/app/upload-keystore.jks"
fi

if [[ "${CHECK_LOCAL_IOS_SIGNING:-0}" == "1" ]]; then
  require_file "mobile/ios/ExportOptions.plist"
  plutil -lint "$ROOT_DIR/mobile/ios/ExportOptions.plist" >/dev/null
fi

echo "Release artifact preflight checks passed."
