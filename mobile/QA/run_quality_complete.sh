#!/usr/bin/env bash
set -euo pipefail

WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$WORKDIR"

export ANDROID_PREFER_EMULATOR=1
export REQUIRE_ANDROID_EMULATOR=1
if [ -z "${LEDGER_E2E_AUTO_AUTH:-}" ] && [ -n "${LEDGER_E2E_SERVER_URL:-}" ] && [ -n "${LEDGER_E2E_PASSWORD:-}" ]; then
  export LEDGER_E2E_AUTO_AUTH=true
fi

export HOME="${HOME_OVERRIDE:-/private/tmp}"

printf '=== 1/2 静态质量闸门 ===\n'
./QA/run_ui_quality_gate.sh

printf '\n=== 2/2 运行时闸门（如有设备） ===\n'
if ./QA/check_device_readiness.sh >/tmp/qa_readiness.log 2>&1; then
  :
else
  READY_CODE=$?
  printf '[信息] 未检测到可直接用于运行时采样的在线设备（退出码: %s）。\n' "$READY_CODE"
  echo "原因和建议请查看：/tmp/qa_readiness.log"
  echo "---"
  cat /tmp/qa_readiness.log
  exit 0
fi

ANDROID_PREFER_EMULATOR=1 ./QA/android_install.sh

if [ "$#" -gt 0 ]; then
  ANDROID_PREFER_EMULATOR=1 ./QA/run_android_runtime_gate.sh "$@"
else
  ANDROID_PREFER_EMULATOR=1 ./QA/run_android_runtime_gate.sh
fi
