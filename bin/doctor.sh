#!/bin/bash
# doctor.sh — 檢查本 repo 的執行環境：命令存在與種類、core.hooksPath 的來源
# 註記：逐項容錯，捨棄 -e；一項沒過不中斷其餘項，讓使用者一次看到全部缺項
set -uo pipefail

fail=0

# 必要命令：need <命令> <種類說明> <種類樣式> <取樣指令...>；樣式比對取樣指令的輸出
need() {
  local cmd="$1"
  local kind="$2"
  local pattern="$3"
  local out

  shift 3
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Error: 找不到 ${cmd}（${kind}）" >&2
    fail=1
    return 0
  fi
  out="$("$@" 2>&1 || true)"
  if [[ ! "${out}" =~ ${pattern} ]]; then
    echo "Error: ${cmd} 不是 ${kind}" >&2
    fail=1
    return 0
  fi
  printf 'Info: %s 是 %s\n' "${cmd}" "${kind}"
}

# 選用命令：want <命令> <缺了影響什麼>；缺了只提示，task lint 與 task test 仍跑得完
want() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Info: 找不到 $1，$2"
  fi
}

# main
# go-task 的 --version 只印版本號，認不出種類，改看 --help 的開頭說明（task 3.54.0 實測）
need task 'go-task' 'Falls back to the "default" task' task --help
need python3 'Python 3' '^Python 3\.' python3 --version
# bin/sync-lint.py 要 PyYAML，task lint 會跑它
need python3 'Python 3 加 PyYAML' '^ok$' python3 -c 'import yaml; print("ok")'
need shellcheck 'ShellCheck' 'ShellCheck' shellcheck --version
need gitleaks 'gitleaks' 'Gitleaks scans code' gitleaks --help
# 建置與推送全部走 sudo podman、sudo skopeo
need sudo 'sudo' '^Sudo version' sudo --version
need podman 'podman' '^podman version' podman --version
need skopeo 'skopeo' '^skopeo version' skopeo --version

want kubectl 'apply:cronjob、apply:namespace 跑不了；tests/test_cronjob.sh 的真產物斷言印 [SKIP]，task test 照樣綠，改了 sync/ 要在有 kubectl 的機器重跑'

# testfile 由 smoke:image 跑，try:image 與 ci:image 也會呼叫它
want sshpass 'testfile 登入不了容器，smoke:image、try:image、ci:image 跑不了'
want jq 'testfile 取不到容器 IP，smoke:image、try:image、ci:image 跑不了'
want ssh 'testfile 登入不了容器，smoke:image、try:image、ci:image 跑不了'
want xfreerdp 'rdp 桌面層的 testfile 會 [FAIL]'

# local 或 worktree 作用域的 core.hooksPath 會讓 git 不經過帳號層派工 hook，機密掃描靜默失效
scopes="$(git config --show-scope --get-all core.hooksPath || true)"
if [[ "${scopes}" =~ (^|$'\n')(local|worktree)$'\t' ]]; then
  echo "Error: core.hooksPath 有 local 或 worktree 來源，帳號層的機密掃描不會跑。修法：" >&2
  echo "  git config --local --unset core.hooksPath" >&2
  fail=1
fi

if [[ "${fail}" -eq 0 ]]; then
  echo "Success: 執行環境齊全"
fi
exit "${fail}"
