#!/bin/bash
# smoke-run.sh — bigdata 的煙霧測試共用段：在容器內以 login shell 跑一段指令，輸出要比對到每個樣式
# 驅動：smoke-<service>.sh，參數是容器名、service 名、指令與一到多個 ERE 樣式
# 註記：要用 bash -lc，login shell 才讀 /etc/profile.d/*-env.sh；只靠 ENV 會漏掉 profile.d 壞掉的情形
set -euo pipefail

# main
(( $# >= 4 )) || { echo "[FAIL] usage: smoke-run.sh <container> <service> <command> <pattern>..." >&2; exit 1; }
c="$1"
svc="$2"
cmd="$3"
shift 3

# 照舊 testfile 的判法：指令的結束碼不算數，只看輸出比對得到樣式
out="$(docker exec "${c}" bash -lc "${cmd}" 2>&1)" || true
printf '%s\n' "${out}"

fail=0
for pat in "$@"; do
  if grep -qE -- "${pat}" <<<"${out}"; then
    echo "[OK] ${svc}: ${pat}"
  else
    echo "[FAIL] ${svc}: output does not match ${pat}" >&2
    fail=1
  fi
done
(( fail == 0 )) || exit 1
echo "[OK] bigdata:${svc} smoke test passed"
