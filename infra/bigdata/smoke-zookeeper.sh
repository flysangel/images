#!/bin/bash
# smoke-zookeeper.sh — bigdata:zookeeper 的煙霧測試：ZooKeeper 是 3.8.4
# 驅動：imgctl test（tests.yaml 的 script），參數是容器名
set -euo pipefail

[[ -n "${1:-}" ]] || { echo "[FAIL] usage: smoke-zookeeper.sh <container>" >&2; exit 1; }

base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${base_dir}/smoke-run.sh" "$1" zookeeper \
  '"${ZOOKEEPER_HOME}"/bin/zkServer.sh version' \
  '3\.8\.4'
