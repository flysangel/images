#!/bin/bash
# smoke-hadoop-ha.sh — bigdata:hadoop-ha 的煙霧測試：hdstart 是 HA 版（journalnode 或 zkfc），hadoop 是 3.4.0
# 驅動：imgctl test（tests.yaml 的 script），參數是容器名
set -euo pipefail

[[ -n "${1:-}" ]] || { echo "[FAIL] usage: smoke-hadoop-ha.sh <container>" >&2; exit 1; }

base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${base_dir}/smoke-run.sh" "$1" hadoop-ha \
  'grep -qE "journalnode|zkfc" /bin/hdstart && echo HA-hdstart-ok; hadoop version' \
  'HA-hdstart-ok' \
  'Hadoop 3\.4\.0'
