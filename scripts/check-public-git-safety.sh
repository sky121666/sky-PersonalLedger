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

secret_matches="$(
  git grep -Il -E 'BEGIN (RSA |OPENSSH |EC |DSA |PRIVATE )?PRIVATE KEY|AKIA[0-9A-Z]{16}|github_pat_[A-Za-z0-9_]{30,}|ghp_[A-Za-z0-9_]{30,}|AIza[0-9A-Za-z_-]{35}|sk-[0-9A-Fa-f]{32,}' -- . ':!web/pnpm-lock.yaml' ':!backend/go.sum' ':!mobile/ios/Podfile.lock' ':!mobile/macos/Podfile.lock' || true
)"
if [[ -n "$secret_matches" ]]; then
  echo "ERROR: high-confidence secret pattern found in tracked files" >&2
  echo "$secret_matches" >&2
  fail=1
fi

unsafe_jwt_placeholders='LEDGER_JWT_SECRET=(change-me|change-this-secret|change-this-to-a-random-secret-key|please-change-this-to-a-random-secret-key|your-jwt-secret-change-this-in-production|your-random-secret-key)'
if git grep -nI -E "$unsafe_jwt_placeholders" -- Dockerfile docker-compose.yml .env.example config.example.yaml README.md 2>/dev/null; then
  echo "ERROR: unsafe Docker JWT placeholder is tracked" >&2
  fail=1
fi

if git grep -nI -E 'secret: "(change-me|change-this-secret|change-this-to-a-random-secret-key|please-change-this-to-a-random-secret-key|your-jwt-secret-change-this-in-production|your-random-secret-key)"' -- config.example.yaml 2>/dev/null; then
  echo "ERROR: unsafe config JWT placeholder is tracked" >&2
  fail=1
fi

exit "$fail"
