#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOLVER="$ROOT_DIR/scripts/resolve-release-version.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
  printf 'release version safety test: %s\n' "$1" >&2
  exit 1
}

assert_mobile_success() {
  local version_input="$1"
  local build_number_input="$2"
  local expected_version="$3"
  local output_file="$TMP_DIR/output-success"
  local actual

  : >"$output_file"
  GITHUB_OUTPUT="$output_file" \
    INPUT_VERSION="$version_input" \
    INPUT_BUILD_NUMBER="$build_number_input" \
    "$RESOLVER" --require-build-number
  actual="$(cat "$output_file")"
  [[ "$actual" == "VERSION=$expected_version"$'\n'"BUILD_NUMBER=$build_number_input" ]] ||
    fail "unexpected canonical output for an accepted mobile version"
}

assert_version_only_success() {
  local version_input="$1"
  local expected_version="$2"
  local output_file="$TMP_DIR/output-version-only"
  local actual

  : >"$output_file"
  GITHUB_OUTPUT="$output_file" INPUT_VERSION="$version_input" \
    "$RESOLVER" --version-only
  actual="$(cat "$output_file")"
  [[ "$actual" == "VERSION=$expected_version" ]] ||
    fail "unexpected canonical output for an accepted version-only value"
}

assert_version_rejected() {
  local version_input="$1"
  local output_file="$TMP_DIR/output-rejected-version"

  : >"$output_file"
  if GITHUB_OUTPUT="$output_file" INPUT_VERSION="$version_input" \
    INPUT_BUILD_NUMBER=42 "$RESOLVER" --require-build-number >/dev/null 2>&1; then
    fail "unsafe or invalid version input was accepted"
  fi
  [[ ! -s "$output_file" ]] || fail "rejected version produced partial output"
}

assert_build_number_rejected() {
  local build_number_input="$1"
  local output_file="$TMP_DIR/output-rejected-build"

  : >"$output_file"
  if GITHUB_OUTPUT="$output_file" INPUT_VERSION=1.2.3 \
    INPUT_BUILD_NUMBER="$build_number_input" \
    "$RESOLVER" --require-build-number >/dev/null 2>&1; then
    fail "unsafe or invalid build number input was accepted"
  fi
  [[ ! -s "$output_file" ]] || fail "rejected build number produced partial output"
}

assert_mobile_success 1.2.3 42 1.2.3
assert_mobile_success v1.2.3 00042 1.2.3
assert_mobile_success 0.0.0-alpha.1 0 0.0.0-alpha.1
assert_version_only_success v2.4.6 2.4.6

invalid_versions=(
  ''
  v
  1.2
  1.2.3.4
  01.2.3
  1.02.3
  1.2.03
  1.2.3-01
  1.2.3-alpha..1
  1.2.3+
  1.2.3+build.5
  '1.2.3;id'
  '1$(id)'
  '1.2.3$(id)'
  '"1.2.3"'
  "1.2.3'"
  '1.2.3/foo'
  '1.2.3`id`'
  ' 1.2.3'
  $'1.2.3\nwhoami'
)
for version_input in "${invalid_versions[@]}"; do
  assert_version_rejected "$version_input"
done

invalid_build_numbers=(
  ''
  -1
  1.0
  '1;id'
  '1$(id)'
  '"1"'
  "1'"
  '1/2'
  '1 2'
  $'1\n2'
)
for build_number_input in "${invalid_build_numbers[@]}"; do
  assert_build_number_rejected "$build_number_input"
done

marker="$TMP_DIR/injection-marker"
assert_version_rejected "1.2.3\$(touch $marker)"
[[ ! -e "$marker" ]] || fail "version input executed a shell command"
assert_build_number_rejected "1\$(touch $marker)"
[[ ! -e "$marker" ]] || fail "build number input executed a shell command"

if GITHUB_OUTPUT="$TMP_DIR/output-missing-build" INPUT_VERSION=1.2.3 \
  "$RESOLVER" --require-build-number >/dev/null 2>&1; then
  fail "required empty build number was accepted"
fi
if INPUT_VERSION=1.2.3 "$RESOLVER" --version-only >/dev/null 2>&1; then
  fail "missing GITHUB_OUTPUT was accepted"
fi

python3 - "$ROOT_DIR" <<'PY'
import pathlib
import re
import sys


root = pathlib.Path(sys.argv[1])
workflow_names = (
    "docker",
    "android",
    "ios",
    "macos",
    "windows",
    "release",
    "release-web",
)
failures = []

for name in workflow_names:
    path = root / ".github" / "workflows" / f"{name}.yml"
    lines = path.read_text(encoding="utf-8").splitlines()
    source = "\n".join(lines)
    if "scripts/resolve-release-version.sh" not in source:
        failures.append(f"{path}: missing centralized version resolver")
    if "scripts/check-version-consistency.sh" not in source:
        failures.append(f"{path}: missing repository version consistency check")

    if name in {"release", "release-web"} and not re.search(
        r"prerelease:.*contains\(needs\.prepare\.outputs\.version, '-'\)", source
    ):
        failures.append(f"{path}: prerelease versions must be marked as prereleases")

    for index, line in enumerate(lines):
        match = re.match(r"^(\s*)run:\s*(.*)$", line)
        if match is None:
            continue
        run_indent = len(match.group(1))
        value = match.group(2)
        run_lines = [(index + 1, value)]
        if value in {"|", ">", "|-", ">-", "|+", ">+"}:
            run_lines = []
            for child_index in range(index + 1, len(lines)):
                child = lines[child_index]
                child_indent = len(child) - len(child.lstrip(" "))
                if child.strip() and child_indent <= run_indent:
                    break
                run_lines.append((child_index + 1, child))
        for line_number, run_line in run_lines:
            if "${{" in run_line:
                failures.append(
                    f"{path}:{line_number}: GitHub expression is interpolated directly in run"
                )

docker_workflow = (root / ".github" / "workflows" / "docker.yml").read_text(
    encoding="utf-8"
)
if not re.search(
    r"type=raw,value=latest,enable=.*inputs\.publish_latest"
    r".*!contains\(steps\.version\.outputs\.VERSION, '-'\)",
    docker_workflow,
):
    failures.append("docker workflow must not update latest for prerelease versions")

if failures:
    raise SystemExit("\n".join(failures))
PY

echo "Release version safety tests passed."
