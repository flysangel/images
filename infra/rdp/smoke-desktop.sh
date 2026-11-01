#!/bin/bash
# smoke-desktop.sh — rdp 桌面層的煙霧測試：sshd 可登入、指定指令在 PATH、xfreerdp 從 host 以 RDP 登入並維持 30 秒
# 驅動：smoke-lxqt.sh、smoke-xfce4.sh，參數是容器名與要檢查的指令；:3389 的 listen 由 tests.yaml 的 wait_port 先等過
# 註記：tests.yaml 的 ssh 設 null，imgctl 才把容器名傳給 script；所以容器 IP、:22 與 ssh 登入由本腳本自己做
set -euo pipefail

# 給 trap 用：xfreerdp 的程序群組
XFREERDP_PID=""

cleanup() {
  if [[ -n "${XFREERDP_PID}" ]]; then
    kill -TERM -- "-${XFREERDP_PID}" 2>/dev/null || true
  fi
}

# main
(( $# >= 2 )) || { echo "[FAIL] usage: smoke-desktop.sh <container> <command>..." >&2; exit 1; }
c="$1"
shift

# FreeRDP 2 的指令是 xfreerdp，FreeRDP 3 改名 xfreerdp3，選項相同
rdp_bin=""
for b in xfreerdp xfreerdp3; do
  if command -v "${b}" >/dev/null 2>&1; then
    rdp_bin="${b}"
    break
  fi
done
[[ -n "${rdp_bin}" ]] || { echo "[FAIL] xfreerdp not installed on host (install freerdp3-x11)" >&2; exit 1; }

# 沒有 X display 的 host（例如 CI）用 xvfb-run 給 xfreerdp 一個虛擬 display
rdp_cmd=("${rdp_bin}")
if [[ -z "${DISPLAY:-}" ]]; then
  command -v xvfb-run >/dev/null 2>&1 \
    || { echo "[FAIL] no DISPLAY and xvfb-run not installed on host (install xvfb)" >&2; exit 1; }
  rdp_cmd=(xvfb-run -a "${rdp_bin}")
fi

ip="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{"\n"}}{{end}}' "${c}" | awk 'NF { print; exit }')"
[[ -n "${ip}" ]] || { echo "[FAIL] cannot get IP of ${c}" >&2; exit 1; }

# CMD 先起 xrdp 再起 sshd，:3389 先通不代表 :22 也通，等最多 60 秒
for _ in $(seq 1 30); do
  if (exec 3<>"/dev/tcp/${ip}/22") 2>/dev/null; then
    break
  fi
  sleep 2
done
(exec 3<>"/dev/tcp/${ip}/22") 2>/dev/null \
  || { echo "[FAIL] sshd not listening on ${ip}:22" >&2; exit 1; }

sshpass -p bigred ssh \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  "bigred@${ip}" 'echo ssh test ok' >/dev/null \
  || { echo "[FAIL] ssh login failed for bigred@${ip}" >&2; exit 1; }

for bin in "$@"; do
  docker exec "${c}" sh -c "command -v ${bin}" >/dev/null \
    || { echo "[FAIL] ${bin} not in PATH" >&2; exit 1; }
done

# setsid 讓 xfreerdp（與 xvfb-run 起的 Xvfb）自成一個程序群組，結束時整組一起收掉
trap cleanup EXIT
echo "[test] ${rdp_bin} connecting to ${ip}:3389, holding for 30s..."
setsid "${rdp_cmd[@]}" \
  /v:"${ip}:3389" \
  /u:bigred /p:bigred \
  /cert:ignore \
  /log-level:WARN </dev/null >/dev/null 2>&1 &
XFREERDP_PID=$!
sleep 5
kill -0 "${XFREERDP_PID}" 2>/dev/null \
  || { echo "[FAIL] ${rdp_bin} died within 5s of starting" >&2; exit 1; }
sleep 25
kill -0 "${XFREERDP_PID}" 2>/dev/null \
  || { echo "[FAIL] ${rdp_bin} died before 30s mark" >&2; exit 1; }

echo "[OK] rdp desktop smoke test passed: ${c}"
