#!/bin/bash
# smoke.sh — fbs:base 的煙霧測試：filebrowser 在 PATH，且 :4000 回 HTTP
# 驅動：imgctl test（tests.yaml 的 script），參數是容器名；:4000 的 listen 由 wait_port 先等過
set -euo pipefail

[[ -n "${1:-}" ]] || { echo "[FAIL] usage: smoke.sh <container>" >&2; exit 1; }
c="$1"

docker exec "${c}" sh -c 'command -v filebrowser' >/dev/null \
    || { echo "[FAIL] filebrowser not in PATH" >&2; exit 1; }

# filebrowser 的 / 會 redirect 到 /login，回 200 或 30x
http_code="$(docker exec "${c}" curl -sS -o /dev/null -w '%{http_code}' http://localhost:4000/ 2>/dev/null || true)"
case "${http_code}" in
    200|301|302|307|308) ;;
    *)
        echo "[FAIL] filebrowser HTTP / returned ${http_code} (expected 200 or 30x)" >&2
        exit 1
        ;;
esac

echo "[OK] fbs smoke test passed"
