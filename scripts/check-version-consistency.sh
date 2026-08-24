#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  printf 'version consistency: %s\n' "$1" >&2
  exit 1
}

[[ "$#" -le 1 ]] || fail "usage: check-version-consistency.sh [release-version]"

project_version="$(tr -d '[:space:]' <"$ROOT_DIR/VERSION")"
core_number='(0|[1-9][0-9]*)'
prerelease_identifier='(0|[1-9][0-9]*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*)'
project_semver_regex="^${core_number}\\.${core_number}\\.${core_number}(-${prerelease_identifier}(\\.${prerelease_identifier})*)?$"
[[ "$project_version" =~ $project_semver_regex ]] ||
  fail "VERSION must contain SemVer without build metadata"

web_version="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["version"])' "$ROOT_DIR/web/package.json")"
mobile_version="$(sed -nE 's/^version:[[:space:]]*([^+[:space:]]+)(\+[^[:space:]]+)?$/\1/p' "$ROOT_DIR/mobile/pubspec.yaml")"

[[ "$web_version" == "$project_version" ]] ||
  fail "web/package.json version $web_version does not match VERSION $project_version"
[[ "$mobile_version" == "$project_version" ]] ||
  fail "mobile/pubspec.yaml version $mobile_version does not match VERSION $project_version"

release_version="${1:-${RELEASE_VERSION-}}"
release_version="${release_version#v}"
if [[ -n "$release_version" && "$release_version" != "$project_version" ]]; then
  fail "release version $release_version does not match VERSION $project_version"
fi

printf 'Version consistency checks passed: %s\n' "$project_version"
