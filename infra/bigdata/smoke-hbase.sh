#!/bin/bash
# smoke-hbase.sh — bigdata:hbase 的煙霧測試：login shell 的 hbase 是 2.5.8
# 驅動：imgctl test（tests.yaml 的 script），參數是容器名
set -euo pipefail

[[ -n "${1:-}" ]] || { echo "[FAIL] usage: smoke-hbase.sh <container>" >&2; exit 1; }

base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${base_dir}/smoke-run.sh" "$1" hbase \
  'hbase version' \
  '2\.5\.8'
