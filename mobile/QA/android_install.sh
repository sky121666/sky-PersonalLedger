#!/usr/bin/env bash

set -euo pipefail

FLUTTER_BIN="${FLUTTER_BIN:-/private/tmp/sky-personalledger-flutter-sdk/flutter/bin/flutter}"
ADB_BIN="${ADB_BIN:-adb}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOBILE_DIR="$PROJECT_ROOT/mobile"

if ! command -v "$ADB_BIN" >/dev/null 2>&1; then
  echo "[错误] adb 未安装或未在 PATH。"
  echo "请先在本机安装 Android SDK Platform Tools，并确认 adb 可执行。"
  exit 1
fi

if [ ! -x "$FLUTTER_BIN" ]; then
  if command -v flutter >/dev/null 2>&1; then
    FLUTTER_BIN="$(command -v flutter)"
  else
    echo "[错误] Flutter SDK 未找到。请设置 FLUTTER_BIN 或确保 flutter 在 PATH。"
    exit 1
  fi
fi

DEVICES_RAW="$($ADB_BIN devices -l | awk 'NR>1 && $2 == "device" {print $1}')"
if [ -z "$DEVICES_RAW" ]; then
  echo "[错误] 未检测到授权且在线的 Android 设备。"
  echo "排查项："
  echo "1) USB 线是否稳定、数据线是否支持调试"
  echo "2) 手机是否开启了开发者模式和 USB 调试"
  echo "3) 电脑是否弹出授权提示并已确认"
  echo "4) 执行 adb devices -l 查看状态（unauthorized/offline/device）"
  exit 2
fi

SELECTED_DEVICE="${1:-$(printf '%s\n' "$DEVICES_RAW" | awk 'NR==1 {print $1}')}"
if ! printf '%s\n' "$DEVICES_RAW" | awk -v selected="$SELECTED_DEVICE" '$0 == selected {found=1} END {exit !found}'; then
  echo "[错误] 指定设备不在当前在线列表：$SELECTED_DEVICE"
  echo "可用设备："
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    echo " - $d"
  done <<< "$DEVICES_RAW"
  exit 3
fi

cd "$MOBILE_DIR"
echo "[执行] flutter install -d $SELECTED_DEVICE"
HOME=/tmp FLUTTER_SUPPRESS_ANALYTICS=true DART_SUPPRESS_ANALYTICS=true "$FLUTTER_BIN" install -d "$SELECTED_DEVICE"

echo "[完成] 已尝试对设备 $SELECTED_DEVICE 执行安装，若无错误即安装成功。"
