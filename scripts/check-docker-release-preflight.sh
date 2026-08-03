#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

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

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "$1 is required" >&2
    exit 1
  fi
}

check_compose_modes() {
  local base_config="$TMP_DIR/base-compose.json"
  local debug_config="$TMP_DIR/debug-compose.json"
  local jwt_secret="docker-release-preflight-only-32-characters"
  local setup_token="docker-release-setup-token-only-32-characters"

  LEDGER_JWT_SECRET="$jwt_secret" LEDGER_SETUP_TOKEN="$setup_token" docker compose --env-file /dev/null \
    -f "$ROOT_DIR/docker-compose.yml" \
    config --format json >"$base_config"
  LEDGER_JWT_SECRET="$jwt_secret" LEDGER_SETUP_TOKEN="$setup_token" docker compose --env-file /dev/null \
    -f "$ROOT_DIR/docker-compose.yml" \
    -f "$ROOT_DIR/docker-compose.debug.yml" \
    config --format json >"$debug_config"

  python3 - "$base_config" "$debug_config" <<'PY'
import json
import sys


def service_environment(path):
    with open(path, encoding="utf-8") as handle:
        config = json.load(handle)
    try:
        environment = config["services"]["personal-ledger"]["environment"]
    except (KeyError, TypeError) as error:
        raise SystemExit(f"Invalid personal-ledger Compose service in {path}: {error}")
    if not isinstance(environment, dict):
        raise SystemExit(f"Compose environment must resolve to a mapping in {path}")
    return environment


base = service_environment(sys.argv[1])
debug = service_environment(sys.argv[2])
if base.get("LEDGER_SERVER_MODE") != "release":
    raise SystemExit("Base docker-compose.yml must resolve LEDGER_SERVER_MODE=release")
if debug.get("LEDGER_SERVER_MODE") != "debug":
    raise SystemExit("Debug override must resolve LEDGER_SERVER_MODE=debug")
for label, environment in (("base", base), ("debug", debug)):
    if environment.get("LEDGER_CORS_ALLOWED_ORIGINS", "").strip() == "*":
        raise SystemExit(f"{label} Compose configuration must not allow wildcard CORS")
    if str(environment.get("LEDGER_SECURITY_ALLOW_PRIVATE_OUTBOUND", "")).lower() != "false":
        raise SystemExit(f"{label} Compose configuration must block private outbound networks by default")
    if str(environment.get("LEDGER_STORAGE_RESTORE_MAX_FILE_SIZE", "")) != "64":
        raise SystemExit(f"{label} Compose configuration must cap restore uploads")
PY
}

require_file ".github/workflows/docker.yml"
require_file ".github/workflows/release.yml"
require_file "Dockerfile"
require_file "docker-entrypoint.sh"
require_file "docker-compose.yml"
require_file "docker-compose.debug.yml"
require_file "README.md"
require_file ".env.example"
require_tool docker
require_tool python3

require_text ".github/workflows/docker.yml" "workflow_call"
require_text ".github/workflows/docker.yml" "image_digest"
require_text ".github/workflows/docker.yml" "ghcr\\.io"
require_text ".github/workflows/docker.yml" "docker/build-push-action@[0-9a-f]{40}"
require_text ".github/workflows/docker.yml" "steps\\.build\\.outputs\\.digest"
require_text ".github/workflows/docker.yml" "platforms: linux/amd64,linux/arm64"
require_text ".github/workflows/docker.yml" "push: true"
require_text ".github/workflows/docker.yml" "provenance: mode=max"
require_text ".github/workflows/docker.yml" "sbom: true"
require_text ".github/workflows/docker.yml" "aquasecurity/trivy-action@[0-9a-f]{40}"
require_text ".github/workflows/docker.yml" "image-ref:.*steps\\.build\\.outputs\\.digest"
require_text ".github/workflows/docker.yml" "severity: HIGH,CRITICAL"
require_text ".github/workflows/docker.yml" "type=raw,value=\\$\\{\\{ steps\\.version\\.outputs\\.VERSION \\}\\}"
require_text ".github/workflows/docker.yml" "type=raw,value=latest,enable=\\$\\{\\{ inputs\\.publish_latest \\}\\}"
require_text ".github/workflows/release.yml" "uses: \\.\\/\\.github\\/workflows\\/docker\\.yml"
require_text ".github/workflows/release.yml" "uses: \\.\\/\\.github\\/workflows\\/web\\.yml"
require_text ".github/workflows/release.yml" "docker pull ghcr\\.io/\\$\\{\\{ github\\.repository \\}\\}:\\$\\{\\{ needs\\.prepare\\.outputs\\.version \\}\\}"
require_text ".github/workflows/release.yml" "refs/tags/v\\$\\{\\{ needs\\.prepare\\.outputs\\.version \\}\\}/docker-compose\\.yml"
require_text ".github/workflows/release.yml" "LEDGER_IMAGE=ghcr\\.io/\\$\\{\\{ github\\.repository \\}\\}:\\$\\{\\{ needs\\.prepare\\.outputs\\.version \\}\\}"
require_text ".github/workflows/release.yml" "needs\\.docker\\.outputs\\.image_digest"
require_text ".github/workflows/release.yml" "LEDGER_SERVER_MODE=release"
require_text ".github/workflows/release.yml" "docker compose up -d"

require_text "Dockerfile" "FROM node:24\\.18\\.1-alpine3\\.24@sha256:f70403e87646dc51b45295f4b8b70cdad0b63d2297c4c9899119b03f7af7a6b3 AS frontend-builder"
require_text "Dockerfile" "FROM golang:1\\.26\\.5-alpine3\\.24@sha256:0178a641fbb4858c5f1b48e34bdaabe0350a330a1b1149aabd498d0699ff5fb2 AS backend-builder"
require_text "Dockerfile" "FROM alpine:3\\.24\\.1@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b"
require_text "Dockerfile" "go build -mod=readonly"
require_text ".dockerignore" "backend/\\.codex-go-cache"
require_text ".dockerignore" "output"
require_text "Dockerfile" "HEALTHCHECK"
require_text "Dockerfile" "adduser -S -D -H -u 10001 -G ledger ledger"
require_text "Dockerfile" "ENTRYPOINT \[\"/usr/local/bin/docker-entrypoint\.sh\"\]"
require_text "docker-entrypoint.sh" "exec su-exec ledger:ledger"
require_text "scripts/check-docker-local-smoke.sh" "Runtime UID: 10001"
require_text "scripts/check-docker-compose-local-smoke.sh" "Runtime UID: 10001"
require_text "scripts/check-docker-release-evidence.sh" "Runtime UID: 10001"
require_text "Dockerfile" "LEDGER_OBSERVABILITY_METRICS_ENABLED=false"
require_text "docker-compose.yml" "LEDGER_OBSERVABILITY_METRICS_ENABLED"
require_text "scripts/check-docker-local-smoke.sh" "Metrics auth: PASS"
require_text "scripts/check-docker-compose-local-smoke.sh" "Metrics auth: PASS"
require_text "scripts/check-docker-release-evidence.sh" "Metrics auth: PASS"
require_text "Dockerfile" "output-document=/dev/null http://localhost:8080/api/v1/health"
require_text "Dockerfile" "VOLUME \\[\"/data\"\\]"
require_text "Dockerfile" "LEDGER_SERVER_MODE=release"
require_text "Dockerfile" "LEDGER_DATABASE_PATH=/data/ledger\\.db"
require_text "Dockerfile" "LEDGER_STORAGE_BACKUP_PATH=/data/backups"

require_text "docker-compose.yml" "\\$\\{LEDGER_IMAGE:-ghcr\\.io/sky121666/sky-personalledger:latest\\}"
require_text "docker-compose.yml" "LEDGER_JWT_SECRET=\\$\\{LEDGER_JWT_SECRET:\\?Set LEDGER_JWT_SECRET in \\.env before starting\\}"
require_text "docker-compose.yml" "LEDGER_SETUP_TOKEN=\\$\\{LEDGER_SETUP_TOKEN:\\?Set LEDGER_SETUP_TOKEN in \\.env before starting\\}"
require_text "docker-compose.yml" "\\./data:/data"
require_text ".env.example" "LEDGER_CORS_ALLOWED_ORIGINS="
require_text ".env.example" "LEDGER_SETUP_TOKEN="
require_text ".env.example" "LEDGER_SECURITY_ALLOW_PRIVATE_OUTBOUND=false"
require_text ".env.example" "LEDGER_SERVER_TRUSTED_PROXIES="
require_text ".env.example" "LEDGER_STORAGE_RESTORE_MAX_FILE_SIZE=64"

if grep -qE '^[[:space:]]*LEDGER_CORS_ALLOWED_ORIGINS=[*][[:space:]]*$' "$ROOT_DIR/.env.example"; then
  echo "Release example must not default CORS to wildcard." >&2
  exit 1
fi

check_compose_modes

echo "Docker release preflight checks passed."
