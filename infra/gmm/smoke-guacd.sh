#!/bin/bash
# smoke-guacd.sh — gmm:guacd 的煙霧測試：guacd 執行檔存在且可執行
# 驅動：imgctl test（tests.yaml 的 script），參數是容器名；:4822 的 listen 由 wait_port 先等過
set -euo pipefail

[[ -n "${1:-}" ]] || { echo "[FAIL] usage: smoke-guacd.sh <container>" >&2; exit 1; }
c="$1"

# 上游映像把 guacd 裝在 /opt/guacamole/sbin/，不在 PATH，所以驗路徑不驗 command -v
docker exec "${c}" sh -c 'test -x /opt/guacamole/sbin/guacd' \
  || { echo "[FAIL] /opt/guacamole/sbin/guacd missing or not executable" >&2; exit 1; }

echo "[OK] gmm:guacd smoke test passed"
