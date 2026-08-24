#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
verify_revision="${VERIFY_REVISION:-HEAD}"
verify_worktree="${VERIFY_WORKTREE:-0}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

worktree="$tmp_dir/sky-PersonalLedger"
mkdir -p "$worktree"

archive_revision="$verify_revision"
if [[ "$verify_worktree" == "1" ]]; then
  if [[ "$verify_revision" != "HEAD" ]]; then
    echo "VERIFY_WORKTREE=1 only supports VERIFY_REVISION=HEAD." >&2
    exit 1
  fi
  worktree_index="$tmp_dir/worktree.index"
  GIT_INDEX_FILE="$worktree_index" git -C "$repo_root" read-tree HEAD
  GIT_INDEX_FILE="$worktree_index" git -C "$repo_root" add -u -- . \
    ':(exclude)mobile/QA' \
    ':(exclude)mobile/QA/**'
  while IFS= read -r -d '' path; do
    case "$path" in
      mobile/QA/*) continue ;;
    esac
    GIT_INDEX_FILE="$worktree_index" git -C "$repo_root" add -- "$path"
  done < <(git -C "$repo_root" ls-files --others --exclude-standard -z)
  archive_revision="$(GIT_INDEX_FILE="$worktree_index" git -C "$repo_root" write-tree)"
fi

git -C "$repo_root" archive --format=tar "$archive_revision" | tar -x -C "$worktree"

require_checkout_file() {
  if [[ ! -f "$worktree/$1" ]]; then
    echo "Missing required file in clean-checkout revision $verify_revision: $1" >&2
    exit 1
  fi
}

require_checkout_file "mobile/android/gradle/wrapper/gradle-wrapper.properties"
require_checkout_file "mobile/android/gradle/wrapper/gradle-wrapper.jar"
require_checkout_file "mobile/android/gradlew"
require_checkout_file "mobile/android/gradlew.bat"
require_checkout_file "docker-compose.debug.yml"
require_checkout_file ".github/workflows/web.yml"
require_checkout_file "scripts/resolve-release-version.sh"
require_checkout_file "scripts/test-resolve-release-version.sh"
require_checkout_file "scripts/check-version-consistency.sh"
require_checkout_file "scripts/check-toolchain-consistency.sh"
require_checkout_file "VERSION"
require_checkout_file ".node-version"

(
  cd "$worktree"
  ./scripts/check-docker-release-preflight.sh
  ./scripts/check-release-artifacts-preflight.sh
)

(
  cd "$worktree/backend"
  go test ./...
  go vet ./...
)

if [[ "${RUN_DATABASE_MATRIX:-0}" == "1" ]]; then
  (
    cd "$worktree"
    ./scripts/verify-database-matrix.sh
  )
fi

(
  cd "$worktree/web"
  # A clean-checkout verification must not inherit a partially-pruned shared
  # pnpm store. Keep the dependency content-addressable store inside this
  # disposable run so a corrupt developer cache cannot create false failures.
  pnpm install --frozen-lockfile --store-dir "$tmp_dir/pnpm-store"
  pnpm test
  pnpm verify:attachments
  pnpm run build
  pnpm audit --audit-level=moderate
)

(
  cd "$worktree/mobile"
  flutter pub get
  flutter pub deps --json >"$tmp_dir/flutter-pub-deps.json"
  python3 - "$tmp_dir/flutter-pub-deps.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    dependency_graph = json.load(handle)
webview_packages = sorted(
    package["name"]
    for package in dependency_graph.get("packages", [])
    if "webview" in package.get("name", "").lower()
)
if webview_packages:
    raise SystemExit(
        "Resolved mobile dependency graph contains WebView packages: "
        + ", ".join(webview_packages)
    )
PY
  flutter analyze
  flutter test
  flutter test -d flutter-tester integration_test/app_smoke_test.dart
)

(
  cd "$worktree"
  ./scripts/verify-mobile-e2e.sh
)
