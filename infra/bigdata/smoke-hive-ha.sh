#!/bin/bash
# smoke-hive-ha.sh — bigdata:hive-ha 的煙霧測試：HA hadoop conf 已疊上（dfs.nameservices），hive 執行檔存在
# 驅動：imgctl test（tests.yaml 的 script），參數是容器名
set -euo pipefail

[[ -n "${1:-}" ]] || { echo "[FAIL] usage: smoke-hive-ha.sh <container>" >&2; exit 1; }

base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${base_dir}/smoke-run.sh" "$1" hive-ha \
  'grep -rq dfs.nameservices /conf/hadoop-3.4.0/etc/hadoop/hdfs-site.xml && echo HA-conf-ok; test -x "${HIVE_HOME}/bin/hive" && echo hive-bin-ok' \
  'HA-conf-ok' \
  'hive-bin-ok'
