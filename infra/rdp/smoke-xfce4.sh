#!/bin/bash
# smoke-xfce4.sh — rdp:xfce4 的煙霧測試：交給 smoke-desktop.sh，檢查 xrdp、firefox 與 xfce4-session
# 驅動：imgctl test（tests.yaml 的 script），參數是容器名
set -euo pipefail

[[ -n "${1:-}" ]] || { echo "[FAIL] usage: smoke-xfce4.sh <container>" >&2; exit 1; }

base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${base_dir}/smoke-desktop.sh" "$1" xrdp firefox xfce4-session
