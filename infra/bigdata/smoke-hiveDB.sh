#!/bin/bash
# smoke-hiveDB.sh — bigdata:hiveDB 的煙霧測試：mariadb 執行檔存在，自家 init SQL 已 COPY 且含 sql_mode 修正
# 驅動：imgctl test（tests.yaml 的 script），參數是容器名
set -euo pipefail

[[ -n "${1:-}" ]] || { echo "[FAIL] usage: smoke-hiveDB.sh <container>" >&2; exit 1; }

base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${base_dir}/smoke-run.sh" "$1" hiveDB \
  'command -v mariadbd mysqld mariadb mysql 2>/dev/null | head -1; echo ---SQL---; cat /docker-entrypoint-initdb.d/hive-patch.mysql.sql' \
  '(mariadbd|mysqld|mariadb|mysql)$' \
  'NO_BACKSLASH_ESCAPES'
