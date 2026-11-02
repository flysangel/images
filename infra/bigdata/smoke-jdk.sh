#!/bin/bash
# smoke-jdk.sh — bigdata:jdk 的煙霧測試：login shell 的 java 是 OpenJDK 1.8.0_492
# 驅動：imgctl test（tests.yaml 的 script），參數是容器名
set -euo pipefail

[[ -n "${1:-}" ]] || { echo "[FAIL] usage: smoke-jdk.sh <container>" >&2; exit 1; }

base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${base_dir}/smoke-run.sh" "$1" jdk \
  'java -version' \
  '1\.8\.0_492'
