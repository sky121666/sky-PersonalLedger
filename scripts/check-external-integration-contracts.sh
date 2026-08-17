#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

(
  cd "$repo_root/backend"
  go test ./internal/service \
    -run '^(TestAIProvider|TestAIReport|TestSanitizeAIError|TestNotification|TestSendNotification)' \
    -count=1
)

echo "Deterministic AI, SMTP, webhook, robot, scheduler, SSRF, and secret-handling contracts passed."
echo "Live vendor availability remains an operator check because CI intentionally uses local test servers and transports."
