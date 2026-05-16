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

(
  cd "$worktree/backend"
  go test ./...
  go vet ./...
)

(
  cd "$worktree/web"
  npm ci
  npm run build
)

(
  cd "$worktree/mobile"
  flutter pub get
  flutter analyze
  flutter test
)
