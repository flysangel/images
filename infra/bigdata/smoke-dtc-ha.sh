#!/bin/bash
# smoke-dtc-ha.sh — bigdata:dtc-ha 的煙霧測試：全套 HA client，含 hadoop 3.4.0、hive 4.0.0、hbase、kafka、spark、zk 與 hconfig、hvrc
# 驅動：imgctl test（tests.yaml 的 script），參數是容器名
set -euo pipefail

[[ -n "${1:-}" ]] || { echo "[FAIL] usage: smoke-dtc-ha.sh <container>" >&2; exit 1; }

base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${base_dir}/smoke-run.sh" "$1" dtc-ha \
  'hadoop version; echo "HIVE_HOME=${HIVE_HOME}"; command -v hbase; command -v kafka-topics.sh; command -v spark-submit; command -v zkCli.sh; ls /bin/hconfig /bin/hvrc' \
  'Hadoop 3\.4\.0' \
  'apache-hive-4\.0\.0' \
  'hbase' \
  'kafka-topics\.sh' \
  'spark-submit' \
  'zkCli\.sh' \
  '/bin/hconfig' \
  '/bin/hvrc'
