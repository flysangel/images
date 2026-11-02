#!/bin/bash
# smoke-hive.sh — bigdata:hive 的煙霧測試：HIVE_HOME 是 4.0.0、hive 執行檔存在、MariaDB JDBC 2.7.12 在 lib
# 驅動：imgctl test（tests.yaml 的 script），參數是容器名
set -euo pipefail

[[ -n "${1:-}" ]] || { echo "[FAIL] usage: smoke-hive.sh <container>" >&2; exit 1; }

base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${base_dir}/smoke-run.sh" "$1" hive \
  'echo "HOME=${HIVE_HOME}"; test -x "${HIVE_HOME}/bin/hive" && echo hive-bin-ok; ls "${HIVE_HOME}"/lib/mariadb-java-client-*.jar' \
  'apache-hive-4\.0\.0' \
  'hive-bin-ok' \
  'mariadb-java-client-2\.7\.12\.jar'
