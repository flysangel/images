#!/bin/bash
# smoke-mariadb.sh — gmm:mariadb 的煙霧測試：資料庫起得來，且 guacamole_db 已建立
# 驅動：imgctl test（tests.yaml 的 script），參數是容器名
# 註記：tests.yaml 不能替容器設環境變數，imgctl 以 sleep 起容器，本腳本再帶環境變數 exec 上游 entrypoint 起 mariadbd
set -euo pipefail

[[ -n "${1:-}" ]] || { echo "[FAIL] usage: smoke-mariadb.sh <container>" >&2; exit 1; }
c="$1"

# lab 測試用的假密碼，容器測完即刪
docker exec -d \
  -e MARIADB_ROOT_PASSWORD=dummypass \
  -e MARIADB_DATABASE=guacamole_db \
  "${c}" docker-entrypoint.sh mariadbd \
  || { echo "[FAIL] cannot start mariadbd in ${c}" >&2; exit 1; }

# 首次啟動要跑 initdb.sql 建 schema，比一般啟動慢，等最多 90 秒
# mariadb 11 起 mysqladmin 改名 mariadb-admin
for _ in $(seq 1 45); do
  if docker exec "${c}" sh -c 'mariadb-admin ping -uroot -pdummypass 2>&1 | grep -q "is alive"'; then
    break
  fi
  sleep 2
done

docker exec "${c}" sh -c 'mariadb-admin ping -uroot -pdummypass 2>&1 | grep -q "is alive"' \
  || { echo "[FAIL] mariadb-admin ping failed" >&2; exit 1; }

# 上游 mariadb 映像沒有 ss 與 netstat，改用 SQL 驗連線
docker exec "${c}" sh -c 'mariadb -uroot -pdummypass -e "SHOW DATABASES" 2>&1 | grep -q "guacamole_db"' \
  || { echo "[FAIL] guacamole_db not present (mariadb may not be reachable on :3306)" >&2; exit 1; }

echo "[OK] gmm:mariadb smoke test passed"
