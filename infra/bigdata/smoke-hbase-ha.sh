#!/bin/bash
# smoke-hbase-ha.sh — bigdata:hbase-ha 的煙霧測試：hbstart 是雙 master 版（HBASE_STBY），hbase 是 2.5.8
# 驅動：imgctl test（tests.yaml 的 script），參數是容器名
set -euo pipefail

[[ -n "${1:-}" ]] || { echo "[FAIL] usage: smoke-hbase-ha.sh <container>" >&2; exit 1; }

base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${base_dir}/smoke-run.sh" "$1" hbase-ha \
  'grep -q HBASE_STBY /bin/hbstart && echo HA-hbstart-ok; hbase version' \
  'HA-hbstart-ok' \
  '2\.5\.8'
