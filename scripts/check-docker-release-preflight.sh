#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

require_file ".github/workflows/docker.yml"
require_file ".github/workflows/release.yml"
require_file "Dockerfile"
require_file "docker-compose.yml"
require_file "README.md"
require_file ".env.example"

require_text ".github/workflows/docker.yml" "workflow_call"
require_text ".github/workflows/docker.yml" "image_digest"
require_text ".github/workflows/docker.yml" "ghcr\\.io"
require_text ".github/workflows/docker.yml" "docker/build-push-action@v5"
require_text ".github/workflows/docker.yml" "steps\\.build\\.outputs\\.digest"
require_text ".github/workflows/docker.yml" "platforms: linux/amd64,linux/arm64"
require_text ".github/workflows/docker.yml" "push: true"
require_text ".github/workflows/docker.yml" "type=raw,value=\\$\\{\\{ steps\\.version\\.outputs\\.VERSION \\}\\}"
require_text ".github/workflows/docker.yml" "type=raw,value=latest,enable=\\$\\{\\{ inputs\\.publish_latest \\}\\}"
require_text ".github/workflows/release.yml" "uses: \\.\\/\\.github\\/workflows\\/docker\\.yml"
require_text ".github/workflows/release.yml" "needs: \\[prepare, docker, android, ios\\]"
require_text ".github/workflows/release.yml" "docker pull ghcr\\.io/\\$\\{\\{ github\\.repository \\}\\}:\\$\\{\\{ needs\\.prepare\\.outputs\\.version \\}\\}"
require_text ".github/workflows/release.yml" "refs/tags/v\\$\\{\\{ needs\\.prepare\\.outputs\\.version \\}\\}/docker-compose\\.yml"
require_text ".github/workflows/release.yml" "LEDGER_IMAGE=ghcr\\.io/\\$\\{\\{ github\\.repository \\}\\}:\\$\\{\\{ needs\\.prepare\\.outputs\\.version \\}\\}"
require_text ".github/workflows/release.yml" "needs\\.docker\\.outputs\\.image_digest"
require_text ".github/workflows/release.yml" "LEDGER_SERVER_MODE=release"
require_text ".github/workflows/release.yml" "docker compose up -d"

require_text "Dockerfile" "FROM node:20-alpine AS frontend-builder"
require_text "Dockerfile" "FROM golang:1\\.24-alpine AS backend-builder"
require_text "Dockerfile" "FROM alpine:3\\.19"
require_text "Dockerfile" "HEALTHCHECK"
require_text "Dockerfile" "output-document=/dev/null http://localhost:8080/api/v1/health"
require_text "Dockerfile" "VOLUME \\[\"/data\"\\]"
require_text "Dockerfile" "LEDGER_SERVER_MODE=release"
require_text "Dockerfile" "LEDGER_DATABASE_PATH=/data/ledger\\.db"
require_text "Dockerfile" "LEDGER_STORAGE_BACKUP_PATH=/data/backups"

require_text "docker-compose.yml" "\\$\\{LEDGER_IMAGE:-ghcr\\.io/sky121666/sky-personalledger:latest\\}"
require_text "docker-compose.yml" "LEDGER_JWT_SECRET=\\$\\{LEDGER_JWT_SECRET:\\?Set LEDGER_JWT_SECRET in \\.env before starting\\}"
require_text "docker-compose.yml" "\\./data:/data"
require_text "docker-compose.yml" "LEDGER_SERVER_MODE=release"
require_text "docker-compose.yml" "release 模式禁止使用 \\*"
require_text ".env.example" "LEDGER_CORS_ALLOWED_ORIGINS="
require_text ".env.example" "release 模式会拒绝通配 CORS"

if grep -qE '^[[:space:]]*LEDGER_CORS_ALLOWED_ORIGINS=[*][[:space:]]*$' "$ROOT_DIR/.env.example"; then
  echo "Release example must not default CORS to wildcard." >&2
  exit 1
fi

echo "Docker release preflight checks passed."
