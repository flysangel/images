#!/bin/bash
# smoke-guacamole.sh — gmm:guacamole 的煙霧測試：Tomcat :8080 回 HTTP，且映像帶 guacamole.war
# 驅動：imgctl test（tests.yaml 的 script），參數是容器名；:8080 的 listen 由 wait_port 先等過
set -euo pipefail

[[ -n "${1:-}" ]] || { echo "[FAIL] usage: smoke-guacamole.sh <container>" >&2; exit 1; }
c="$1"

# Tomcat 上游映像沒有 ss 與 netstat，改用 curl 打 HTTP；任何 HTTP 回應都代表 Tomcat 活著
docker exec "${c}" sh -c 'curl -s --max-time 5 -o /dev/null http://localhost:8080/' \
  || { echo "[FAIL] tomcat not responding on :8080" >&2; exit 1; }

# entrypoint 在執行期才把 war 複製到動態的 catalina-base，所以驗映像內的固定路徑
docker exec "${c}" sh -c 'test -f /opt/guacamole/webapp/guacamole.war' \
  || { echo "[FAIL] /opt/guacamole/webapp/guacamole.war missing" >&2; exit 1; }

echo "[OK] gmm:guacamole smoke test passed"
