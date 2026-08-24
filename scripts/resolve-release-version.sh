#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: resolve-release-version.sh --version-only|--require-build-number

Reads INPUT_VERSION and, when required, INPUT_BUILD_NUMBER from the environment.
Writes canonical VERSION and BUILD_NUMBER values to GITHUB_OUTPUT.
EOF
}

fail() {
  printf 'resolve-release-version: %s\n' "$1" >&2
  exit 1
}

if [[ "$#" -ne 1 ]]; then
  usage
  exit 2
fi

case "$1" in
  --version-only)
    require_build_number=0
    ;;
  --require-build-number)
    require_build_number=1
    ;;
  *)
    usage
    exit 2
    ;;
esac

version_input="${INPUT_VERSION-}"
build_number_input="${INPUT_BUILD_NUMBER-}"
output_file="${GITHUB_OUTPUT-}"

[[ -n "$version_input" ]] || fail "INPUT_VERSION is required"
[[ -n "$output_file" ]] || fail "GITHUB_OUTPUT is required"

core_number='(0|[1-9][0-9]*)'
prerelease_identifier='(0|[1-9][0-9]*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*)'
semver_regex="^v?(${core_number}\\.${core_number}\\.${core_number}(-${prerelease_identifier}(\\.${prerelease_identifier})*)?)$"

if [[ ! "$version_input" =~ $semver_regex ]]; then
  fail "INPUT_VERSION must be SemVer without build metadata, with an optional v prefix"
fi
version="${BASH_REMATCH[1]}"

if [[ "$require_build_number" == "1" ]]; then
  [[ -n "$build_number_input" ]] || fail "INPUT_BUILD_NUMBER is required"
  if [[ ! "$build_number_input" =~ ^[0-9]+$ ]]; then
    fail "INPUT_BUILD_NUMBER must contain ASCII digits only"
  fi
fi

{
  printf 'VERSION=%s\n' "$version"
  if [[ "$require_build_number" == "1" ]]; then
    printf 'BUILD_NUMBER=%s\n' "$build_number_input"
  fi
} >>"$output_file"
