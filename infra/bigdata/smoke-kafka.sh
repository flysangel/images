#!/bin/bash
# smoke-kafka.sh — bigdata:kafka 的煙霧測試：Kafka 是 3.7.0
# 驅動：imgctl test（tests.yaml 的 script），參數是容器名
set -euo pipefail

[[ -n "${1:-}" ]] || { echo "[FAIL] usage: smoke-kafka.sh <container>" >&2; exit 1; }

base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${base_dir}/smoke-run.sh" "$1" kafka \
  '"${KAFKA_HOME}"/bin/kafka-topics.sh --version' \
  '3\.7\.0'
