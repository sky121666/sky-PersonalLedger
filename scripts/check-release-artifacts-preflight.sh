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

require_absent_text() {
  local path="$1"
  local pattern="$2"
  if grep -qE "$pattern" "$ROOT_DIR/$path"; then
    echo "Forbidden pattern still present in $path: $pattern" >&2
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

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "$1 is required" >&2
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

check_release_workflow_contract() {
  python3 - "$ROOT_DIR/.github/workflows/release.yml" <<'PY'
import re
import sys


lines = open(sys.argv[1], encoding="utf-8").read().splitlines()


def indentation(line):
    return len(line) - len(line.lstrip(" "))


try:
    release_start = next(
        index for index, line in enumerate(lines) if re.fullmatch(r"  release:\s*", line)
    )
except StopIteration:
    raise SystemExit("release workflow is missing the release job")

release_end = len(lines)
for index in range(release_start + 1, len(lines)):
    if lines[index].strip() and indentation(lines[index]) <= 2:
        release_end = index
        break
release_lines = lines[release_start + 1 : release_end]

needs_index = next(
    (index for index, line in enumerate(release_lines) if re.match(r"^    needs:\s*", line)),
    None,
)
if needs_index is None:
    raise SystemExit("release job is missing needs")
needs_value = release_lines[needs_index].split(":", 1)[1].strip()
if needs_value.startswith("[") and needs_value.endswith("]"):
    actual_needs = [item.strip() for item in needs_value[1:-1].split(",") if item.strip()]
elif needs_value:
    actual_needs = [needs_value]
else:
    actual_needs = []
    for line in release_lines[needs_index + 1 :]:
        if line.strip() and indentation(line) <= 4:
            break
        match = re.match(r"^\s+-\s+([^#\s]+)", line)
        if match:
            actual_needs.append(match.group(1))

expected_needs = {
    "prepare",
    "backend",
    "web",
    "mobile-quality",
    "mobile-e2e",
    "public-git-safety",
    "backup-security",
    "docker",
    "android",
    "verify-android-artifact",
    "ios",
    "verify-ios-artifact",
}
if set(actual_needs) != expected_needs or len(actual_needs) != len(expected_needs):
    raise SystemExit(
        f"release job needs {actual_needs!r}, expected {sorted(expected_needs)!r}"
    )

uses_index = next(
    (
        index
        for index, line in enumerate(release_lines)
        if re.search(r"uses:\s*softprops/action-gh-release@", line)
    ),
    None,
)
if uses_index is None:
    raise SystemExit("release job is missing softprops/action-gh-release")

step_start = uses_index
while step_start >= 0 and not re.match(r"^      -\s+", release_lines[step_start]):
    step_start -= 1
step_end = len(release_lines)
for index in range(uses_index + 1, len(release_lines)):
    if re.match(r"^      -\s+", release_lines[index]):
        step_end = index
        break
release_step = release_lines[max(step_start, 0) : step_end]

files_index = next(
    (index for index, line in enumerate(release_step) if re.match(r"^\s+files:\s*[|>]", line)),
    None,
)
if files_index is None:
    raise SystemExit("release step is missing a multiline files contract")
files_indent = indentation(release_step[files_index])
actual_files = []
for line in release_step[files_index + 1 :]:
    if line.strip() and indentation(line) <= files_indent:
        break
    if line.strip():
        actual_files.append(line.strip())

expected_files = {
    "artifacts/android-release/*.apk",
    "artifacts/android-release/*.apk.sha256",
    "artifacts/android-release/*.aab",
    "artifacts/android-release/*.aab.sha256",
    "artifacts/ios-ipa/*.ipa",
    "artifacts/ios-ipa/*.ipa.sha256",
}
if set(actual_files) != expected_files or len(actual_files) != len(expected_files):
    raise SystemExit(
        f"release files {actual_files!r}, expected {sorted(expected_files)!r}"
    )
PY
}

check_android_release_guard() {
  python3 - "$ROOT_DIR/mobile/android/app/build.gradle.kts" <<'PY'
import re
import sys


source = open(sys.argv[1], encoding="utf-8").read()
source = re.sub(r"/\*.*?\*/", " ", source, flags=re.DOTALL)
source = re.sub(r"//[^\n]*", " ", source)
code = re.sub(r"\s+", " ", source)


def require(pattern, message):
    if re.search(pattern, code) is None:
        raise SystemExit(message)


require(
    r'if \(releaseSigningConfigured\) \{ signingConfig = signingConfigs\.getByName\("release"\) \}',
    "Android release builds must use the configured release signing key",
)
require(
    r'path\.contains\("release"\) && \(path\.contains\("assemble"\) \|\| '
    r'path\.contains\("bundle"\) \|\| path\.contains\("package"\)\)',
    "Android release task detection must cover assemble, bundle, and package tasks",
)
require(
    r'if \(releaseBuildRequested && !releaseSigningConfigured\) '
    r'\{ throw GradleException\(',
    "Android release tasks must fail without release signing",
)
debug_assignment = 'signingConfig = signingConfigs.getByName("debug")'
if debug_assignment in code or "ledgerAllowLocalReleaseDebugSigning" in code:
    raise SystemExit("Android release builds must not support debug-signing fallbacks")
PY
}

require_file ".github/workflows/android.yml"
require_file ".github/workflows/ios.yml"
require_file ".github/workflows/release.yml"
require_file ".github/workflows/web.yml"
require_file ".github/workflows/backend-database.yml"
require_file ".github/workflows/mobile-quality.yml"
require_file ".github/workflows/mobile-e2e.yml"
require_file ".github/workflows/public-git-safety.yml"
require_file ".github/workflows/security-contracts.yml"
require_file ".github/workflows/dependency-review.yml"
require_file ".github/workflows/quality-gate.yml"
require_file ".github/dependabot.yml"
require_file "VERSION"
require_file ".node-version"
require_file "scripts/check-version-consistency.sh"
require_file "scripts/check-toolchain-consistency.sh"
require_file "docs/android-release-signing.md"
require_file "docs/ios-release-signing.md"
require_file "mobile/android/app/build.gradle.kts"
require_file "mobile/ios/Runner/Info.plist"
require_file "mobile/ios/Runner.xcodeproj/project.pbxproj"
require_tool python3

require_text ".github/workflows/android.yml" "ANDROID_KEYSTORE_BASE64"
require_text ".github/workflows/android.yml" "personal-ledger-.*-android\\.apk"
require_text ".github/workflows/android.yml" "personal-ledger-.*-android\\.aab"
require_text ".github/workflows/android.yml" "personal-ledger-.*-android\\.apk\\.sha256"
require_text ".github/workflows/android.yml" "personal-ledger-.*-android\\.aab\\.sha256"
require_text ".github/workflows/android.yml" "Verify Android release signatures"
require_text ".github/workflows/android.yml" ":app:testDebugUnitTest"
require_text ".github/workflows/android.yml" "APKSIGNER.*verify --verbose --print-certs"
require_text ".github/workflows/android.yml" "jarsigner -verify -strict -certs"
require_text ".github/workflows/android.yml" "/usr/local/lib/android/sdk"
require_absent_text ".github/workflows/android.yml" 'sort -V'
require_text ".github/workflows/ios.yml" "IOS_CERTIFICATE_BASE64"
require_text ".github/workflows/ios.yml" "workflow_call"
require_text ".github/workflows/ios.yml" "personal-ledger-.*-ios\\.ipa"
require_text ".github/workflows/ios.yml" "personal-ledger-.*-ios\\.ipa\\.sha256"
require_text ".github/workflows/ios.yml" "Verify iOS IPA signature"
require_text ".github/workflows/ios.yml" "CFBundleIdentifier"
require_text ".github/workflows/ios.yml" "codesign --verify --deep --strict"
require_text ".github/workflows/release.yml" "uses: \\.\\/\\.github\\/workflows\\/ios\\.yml"
require_text ".github/workflows/release.yml" "verify-android-artifact"
require_text ".github/workflows/release.yml" "verify-ios-artifact"
require_text ".github/workflows/release.yml" "runs-on: macos-latest"
require_text ".github/workflows/release.yml" "actions/setup-java@[0-9a-f]{40}"
require_text ".github/workflows/release.yml" "subosito/flutter-action@[0-9a-f]{40}"
require_text ".github/workflows/release.yml" "build-tools;35\\.0\\.0"
require_text ".github/workflows/release.yml" "sdkmanager"
require_text ".github/workflows/release.yml" "actions: read"
require_text ".github/workflows/release.yml" "REQUIRE_ANDROID_ARTIFACTS: '0'"
require_text ".github/workflows/release.yml" "REQUIRE_IOS_ARTIFACT: '1'"
require_text ".github/workflows/release.yml" "check-release-artifact-files\\.sh"
require_text ".github/workflows/release.yml" "REQUIRE_IOS_ARTIFACT: '0'"
require_text ".github/workflows/release.yml" "VERIFY_ARTIFACT_SIGNATURES: '1'"
require_text ".github/workflows/release.yml" "uses: \\.\\/\\.github\\/workflows\\/web\\.yml"
require_text ".github/workflows/release.yml" "uses: \\.\\/\\.github\\/workflows\\/backend-database\\.yml"
require_text ".github/workflows/release.yml" "uses: \\.\\/\\.github\\/workflows\\/mobile-quality\\.yml"
require_text ".github/workflows/release.yml" "uses: \\.\\/\\.github\\/workflows\\/mobile-e2e\\.yml"
require_text ".github/workflows/release.yml" "uses: \\.\\/\\.github\\/workflows\\/public-git-safety\\.yml"
require_text ".github/workflows/release.yml" "uses: \\.\\/\\.github\\/workflows\\/security-contracts\\.yml"
require_text ".github/workflows/security-contracts.yml" "workflow_call"
require_text ".github/workflows/security-contracts.yml" "check-backup-restore-rehearsal\\.sh"
require_text ".github/workflows/security-contracts.yml" "check-backup-api-rehearsal\\.sh"
require_text ".github/workflows/security-contracts.yml" "check-external-integration-contracts\\.sh"
require_text ".github/workflows/security-contracts.yml" "check-ai-privacy-contract\\.sh"
require_text ".github/workflows/dependency-review.yml" "actions/dependency-review-action@[0-9a-f]{40}"
require_text ".github/workflows/dependency-review.yml" "fail-on-severity: high"
require_text ".github/workflows/quality-gate.yml" "name: Project quality gate"
require_text ".github/workflows/quality-gate.yml" "uses: \.\/\.github\/workflows\/web\.yml"
require_text ".github/workflows/quality-gate.yml" "uses: \.\/\.github\/workflows\/backend-database\.yml"
require_text ".github/workflows/quality-gate.yml" "uses: \.\/\.github\/workflows\/mobile-quality\.yml"
require_text ".github/workflows/quality-gate.yml" "uses: \.\/\.github\/workflows\/mobile-e2e\.yml"
require_text ".github/workflows/quality-gate.yml" "uses: \.\/\.github\/workflows\/security-contracts\.yml"
require_text ".github/dependabot.yml" "package-ecosystem: gomod"
require_text ".github/dependabot.yml" "package-ecosystem: npm"
require_text ".github/dependabot.yml" "package-ecosystem: pub"
require_text ".github/dependabot.yml" "package-ecosystem: github-actions"
require_text ".github/dependabot.yml" "package-ecosystem: docker"
require_text ".github/workflows/backend-database.yml" "workflow_call"
require_text ".github/workflows/backend-database.yml" "verify-database-matrix\\.sh"
require_text ".github/workflows/backend-database.yml" "govulncheck@v1\\.6\\.0"
require_text ".github/workflows/backend-database.yml" "govulncheck \\.\\/\\.\\.\\."
require_text ".github/workflows/backend-database.yml" "check-backend-performance\\.sh"
require_text ".github/workflows/mobile-quality.yml" "workflow_call"
require_text ".github/workflows/mobile-quality.yml" "flutter analyze"
require_text ".github/workflows/mobile-quality.yml" "flutter test"
require_text ".github/workflows/mobile-e2e.yml" "workflow_call"
require_text ".github/workflows/mobile-e2e.yml" "verify-mobile-e2e\\.sh"
require_text ".github/workflows/public-git-safety.yml" "workflow_call"
require_text ".github/workflows/public-git-safety.yml" "actionlint@v1\\.7\\.12"
require_text ".github/workflows/public-git-safety.yml" "run: actionlint"
require_text ".github/workflows/public-git-safety.yml" "check-github-actions-pinning\\.sh"
require_text ".github/workflows/web.yml" "workflow_call"
require_text ".github/workflows/web.yml" "pnpm test"
require_text ".github/workflows/web.yml" "pnpm audit --prod --audit-level=high"
require_text ".github/workflows/web.yml" "pnpm verify:attachments"
require_text ".github/workflows/web.yml" "pnpm build"
require_text ".github/workflows/web.yml" "pnpm verify:bundle"
require_text ".github/workflows/web.yml" "playwright install --with-deps chromium"
require_text ".github/workflows/web.yml" "verify-web-e2e\\.sh"
require_text "scripts/check-release-artifact-files.sh" "checksum sidecar must contain exactly one checksum line"
require_text "scripts/check-release-artifact-files.sh" "checksum sidecar filename mismatch"
require_text "mobile/android/app/build.gradle.kts" "ledgerAllowReleaseCleartext"
require_text "mobile/android/app/src/main/AndroidManifest.xml" 'android:usesCleartextTraffic="\$\{usesCleartextTraffic\}"'
require_text "mobile/ios/Runner.xcodeproj/project.pbxproj" "PRODUCT_BUNDLE_IDENTIFIER = com\\.skyapp\\.personalLedger"
require_text "mobile/ios/Runner.xcodeproj/project.pbxproj" "DEVELOPMENT_TEAM = WV9H55K7S3"

check_release_workflow_contract
check_android_release_guard

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
