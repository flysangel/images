#!/bin/bash
# smoke-spark.sh — bigdata:spark 的煙霧測試：login shell 的 spark-submit 是 3.5.1
# 驅動：imgctl test（tests.yaml 的 script），參數是容器名
set -euo pipefail

[[ -n "${1:-}" ]] || { echo "[FAIL] usage: smoke-spark.sh <container>" >&2; exit 1; }

base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${base_dir}/smoke-run.sh" "$1" spark \
  'spark-submit --version' \
  '3\.5\.1'
