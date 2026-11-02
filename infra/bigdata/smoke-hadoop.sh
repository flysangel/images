#!/bin/bash
# smoke-hadoop.sh — bigdata:hadoop 的煙霧測試：login shell 的 hadoop 是 3.4.0
# 驅動：imgctl test（tests.yaml 的 script），參數是容器名
set -euo pipefail

[[ -n "${1:-}" ]] || { echo "[FAIL] usage: smoke-hadoop.sh <container>" >&2; exit 1; }

base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${base_dir}/smoke-run.sh" "$1" hadoop \
  'hadoop version' \
  'Hadoop 3\.4\.0'
