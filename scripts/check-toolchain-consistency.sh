#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  printf 'toolchain consistency: %s\n' "$1" >&2
  exit 1
}

node_version="$(tr -d '[:space:]' <"$ROOT_DIR/.node-version")"
docker_node_version="$(sed -nE 's/^FROM node:([0-9]+\.[0-9]+\.[0-9]+)-.*/\1/p' "$ROOT_DIR/Dockerfile" | head -n 1)"
go_version="$(awk '$1 == "go" { print $2; exit }' "$ROOT_DIR/backend/go.mod")"
docker_go_version="$(sed -nE 's/^FROM golang:([0-9]+\.[0-9]+\.[0-9]+)-.*/\1/p' "$ROOT_DIR/Dockerfile" | head -n 1)"

[[ -n "$node_version" && "$node_version" == "$docker_node_version" ]] ||
  fail "Node version $node_version does not match Docker $docker_node_version"
[[ -n "$go_version" && "$go_version" == "$docker_go_version" ]] ||
  fail "Go version $go_version does not match Docker $docker_go_version"

if ! grep -Fq "node-version-file: '.node-version'" "$ROOT_DIR/.github/workflows/web.yml"; then
  fail "Web CI must read Node from .node-version"
fi

printf 'Toolchain consistency checks passed: Node %s, Go %s\n' "$node_version" "$go_version"
