#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
check_runtime=false
case "${1:-}" in
  "") ;;
  --runtime) check_runtime=true ;;
  *) echo "Usage: $0 [--runtime]" >&2; exit 2 ;;
esac

fail() {
  printf 'toolchain consistency: %s\n' "$1" >&2
  exit 1
}

node_version="$(tr -d '[:space:]' <"$ROOT_DIR/.node-version")"
if [[ "$check_runtime" == true ]]; then
  actual_node="$(node --version)"
  [[ "$actual_node" == "v$node_version" ]] ||
    fail "Active Node $actual_node does not match $node_version; activate the version in .node-version"
fi
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

node --input-type=module - "$ROOT_DIR" "$check_runtime" <<'JS'
import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const root = process.argv[2]
const read = (file) => readFileSync(join(root, file), 'utf8')
const manifest = JSON.parse(read('web/package.json'))
const version = read('.node-version').trim()
const major = Number(version.split('.')[0])
assert.equal(manifest.engines.node, `>=${version} <${major + 1}`, 'Web Node engine must match the pinned major/minimum')
assert.match(manifest.packageManager, /^pnpm@\d+\.\d+\.\d+$/, 'Pin an exact pnpm release')
const pnpm = manifest.packageManager.slice('pnpm@'.length)
if (process.argv[3] === 'true') {
  const actual = execFileSync('pnpm', ['--version'], { cwd: join(root, 'web'), encoding: 'utf8' }).trim()
  assert.equal(actual, pnpm, `Active pnpm must match packageManager (${pnpm})`)
}
assert.ok(read('Dockerfile').includes(`npm install --global pnpm@${pnpm} && pnpm install --frozen-lockfile`), 'Docker must install the manifest pnpm version')
assert.ok(read('.github/workflows/web.yml').includes(`version: ${pnpm}\n`), 'Web CI must use the manifest pnpm version')
console.log(`Package manager consistency checks passed: pnpm ${pnpm}`)
JS

printf 'Toolchain consistency checks passed: Node %s, Go %s\n' "$node_version" "$go_version"
