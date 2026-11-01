#!/bin/bash
# smoke-lxqt.sh — rdp:lxqt 的煙霧測試：交給 smoke-desktop.sh，檢查 xrdp 與 lxqt-session
# 驅動：imgctl test（tests.yaml 的 script），參數是容器名
set -euo pipefail

[[ -n "${1:-}" ]] || { echo "[FAIL] usage: smoke-lxqt.sh <container>" >&2; exit 1; }

base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${base_dir}/smoke-desktop.sh" "$1" xrdp lxqt-session
