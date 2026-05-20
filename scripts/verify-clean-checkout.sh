#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

worktree="$tmp_dir/sky-PersonalLedger"
mkdir -p "$worktree"

git -C "$repo_root" archive --format=tar HEAD | tar -x -C "$worktree"

test -f "$worktree/mobile/android/gradle/wrapper/gradle-wrapper.properties"
test -f "$worktree/mobile/android/gradle/wrapper/gradle-wrapper.jar"
test -f "$worktree/mobile/android/gradlew"
test -f "$worktree/mobile/android/gradlew.bat"

if grep -R -n -E 'Signing with the debug keys|signingConfigs\.getByName\("debug"\)|保留 WebView 兜底|部分低频功能可能通过 WebView|WebView2' \
  "$worktree/README.md" "$worktree/.github" "$worktree/mobile/android"; then
  echo "Release hardening check failed: stale WebView or debug signing reference found." >&2
  exit 1
fi

if grep -n -E 'artifacts/(macos-app|windows-app)|needs: \[prepare, docker, android, macos, windows\]' \
  "$worktree/.github/workflows/release.yml"; then
  echo "Release hardening check failed: unvalidated desktop artifacts are still attached to GitHub Release." >&2
  exit 1
fi

(
  cd "$worktree/backend"
  go test ./...
  go vet ./...
)

(
  cd "$worktree/web"
  npm ci
  npm run build
  npm audit --audit-level=moderate
)

(
  cd "$worktree/mobile"
  flutter pub get
  flutter analyze
  flutter test
  flutter test -d flutter-tester integration_test/app_smoke_test.dart
)

(
  cd "$worktree"
  ./scripts/verify-mobile-e2e.sh
)
