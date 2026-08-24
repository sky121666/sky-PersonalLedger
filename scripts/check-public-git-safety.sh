#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

fail=0

forbidden_tracked='(^|/)(\.env($|\.)|config\.yaml$|key\.properties$|local\.properties$|google-services\.json$|GoogleService-Info\.plist$|.*\.(db|db-shm|db-wal|sqlite|sqlite3|apk|ipa|aab|jks|keystore|p12|pem|key|crt|tsbuildinfo)$|node_modules/|\.dart_tool/|\.gradle/|build/|dist/)'
allowed_tracked='(^|/)(\.env\.example|config\.example\.yaml|mobile/android/key\.properties\.example|mobile/android/gradle/wrapper/gradle-wrapper\.jar|mobile/ios/Podfile\.lock|mobile/macos/Podfile\.lock)$'

while IFS= read -r path; do
  if [[ "$path" =~ $forbidden_tracked && ! "$path" =~ $allowed_tracked ]]; then
    echo "ERROR: tracked file should not be public: $path" >&2
    fail=1
  fi
done < <(git ls-files)

ignored_tracked="$(git ls-files -ci --exclude-standard)"
if [[ -n "$ignored_tracked" ]]; then
  echo "ERROR: files ignored by .gitignore are still tracked:" >&2
  echo "$ignored_tracked" >&2
  fail=1
fi

secret_pattern='BEGIN (RSA |OPENSSH |EC |DSA |PRIVATE )?PRIVATE KEY|AKIA[0-9A-Z]{16}|github_pat_[A-Za-z0-9_]{30,}|ghp_[A-Za-z0-9_]{30,}|glpat-[A-Za-z0-9_-]{20,}|npm_[A-Za-z0-9]{30,}|xox[baprs]-[A-Za-z0-9-]{20,}|AIza[0-9A-Za-z_-]{35}|sk-[0-9A-Fa-f]{32,}|sk-proj-[A-Za-z0-9_-]{20,}|sk-live-[A-Za-z0-9_-]{20,}|sk-ant-api03-[A-Za-z0-9_-]{20,}'
secret_matches="$(
  git grep --untracked -Il -E "$secret_pattern" -- . ':!web/pnpm-lock.yaml' ':!backend/go.sum' ':!mobile/ios/Podfile.lock' ':!mobile/macos/Podfile.lock' || true
)"
if [[ -n "$secret_matches" ]]; then
  echo "ERROR: high-confidence secret pattern found in tracked or untracked public files" >&2
  echo "$secret_matches" >&2
  fail=1
fi

staged_review_artifacts='^(output/|mobile/QA/(design|reports|screenshots)/)'
max_staged_file_bytes="${MAX_STAGED_FILE_BYTES:-5242880}"

while IFS= read -r -d '' path; do
  if [[ "$path" =~ $staged_review_artifacts && "${ALLOW_REVIEW_ARTIFACTS:-0}" != "1" ]]; then
    echo "ERROR: local QA or generated artifact requires explicit review before staging: $path" >&2
    echo "Set ALLOW_REVIEW_ARTIFACTS=1 only after reviewing the artifact intentionally." >&2
    fail=1
  fi

  staged_size="$(git cat-file -s ":$path")"
  if (( staged_size > max_staged_file_bytes )); then
    echo "ERROR: staged file exceeds ${max_staged_file_bytes} bytes: $path ($staged_size bytes)" >&2
    fail=1
  fi

  if git cat-file -p ":$path" | LC_ALL=C grep -IqE "$secret_pattern"; then
    echo "ERROR: high-confidence secret pattern found in staged file: $path" >&2
    fail=1
  fi
done < <(git diff --cached --name-only --diff-filter=ACMR -z)

unsafe_jwt_placeholders='LEDGER_JWT_SECRET=(change-me|change-this-secret|change-this-to-a-random-secret-key|please-change-this-to-a-random-secret-key|your-jwt-secret-change-this-in-production|your-random-secret-key)'
if git grep -nI -E "$unsafe_jwt_placeholders" -- Dockerfile docker-compose.yml .env.example config.example.yaml README.md 2>/dev/null; then
  echo "ERROR: unsafe Docker JWT placeholder is tracked" >&2
  fail=1
fi

if git grep -nI -E 'secret: "(change-me|change-this-secret|change-this-to-a-random-secret-key|please-change-this-to-a-random-secret-key|your-jwt-secret-change-this-in-production|your-random-secret-key)"' -- config.example.yaml 2>/dev/null; then
  echo "ERROR: unsafe config JWT placeholder is tracked" >&2
  fail=1
fi

if git grep -nI -E 'sk-your-[A-Za-z0-9_-]*|your-(store|key)-password|storePassword=change-me|keyPassword=change-me' -- README.md docker-compose.yml docs mobile/android/key.properties.example 2>/dev/null; then
  echo "ERROR: secret-shaped placeholder is tracked; use neutral angle-bracket placeholders instead" >&2
  fail=1
fi

"$PWD/scripts/check-version-consistency.sh"
"$PWD/scripts/check-toolchain-consistency.sh"

exit "$fail"
