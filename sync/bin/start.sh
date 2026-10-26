#!/bin/bash
# start.sh — skopeo 上游同步，逐檔同步、結尾回報失敗的映像
# 用法: bash sync/bin/start.sh  (env 提供 6 組必要憑證+GHCR 可選——本機由 task mirror 的 dotenv
#       自 sync/secret/secret.env 注入;非憑證常數自帶預設;DEST 內建預設值,可用 DEST= 覆寫)
# 註記：逐項容錯，捨棄 -e；單一登入或單張映像失敗不中止整批，失敗的映像累計到迴圈後一次回報並以 rc=1 結束
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 6 組憑證:必須由 env 提供(叢集=Secret;本機=task dotenv 讀 sync/secret/secret.env)——缺則 fail-fast(優於靜默空字串)
: "${DOCKER_USERNAME:?需由 env/Secret 提供}" "${DOCKER_PASSWORD:?需由 env/Secret 提供}"
: "${REDHAT_USERNAME:?需由 env/Secret 提供}" "${REDHAT_PASSWORD:?需由 env/Secret 提供}"
: "${QUAY_USERNAME:?需由 env/Secret 提供}" "${QUAY_PASSWORD:?需由 env/Secret 提供}"
# 5 非憑證常數:自帶預設(前 4 忠實沿用舊值,GHCR 為新增;皆無尾斜線→不觸 forbidden)
: "${YAML_REGEX:=*.yaml}" "${DOCKER:=docker.io}" "${REDHAT:=registry.redhat.io}" "${QUAY:=quay.io}" "${GHCR:=ghcr.io}"
# DEST 尾斜線是硬契約("${DEST}${image}" 字串相接);呼叫端可用 DEST= 覆寫
DEST="${DEST:-quay.io/flysangel/}"

# 登入段:密碼走 --password-stdin 不落 argv(防 ps 可見);GHCR 可選——有憑證才登入,無則匿名拉取(公開映像可行,可能被 GitHub 限流)
echo "Info: [${DOCKER}]" && printf '%s' "${DOCKER_PASSWORD}" | sudo skopeo login -u="${DOCKER_USERNAME}" --password-stdin "${DOCKER}"
echo "Info: [${REDHAT}]" && printf '%s' "${REDHAT_PASSWORD}" | sudo skopeo login -u="${REDHAT_USERNAME}" --password-stdin "${REDHAT}"
echo "Info: [${QUAY}]" && printf '%s' "${QUAY_PASSWORD}" | sudo skopeo login -u="${QUAY_USERNAME}" --password-stdin "${QUAY}"
if [[ -n "${GHCR_USERNAME:-}" && -n "${GHCR_PASSWORD:-}" ]]; then
  echo "Info: [${GHCR}]" && printf '%s' "${GHCR_PASSWORD}" | sudo skopeo login -u="${GHCR_USERNAME}" --password-stdin "${GHCR}"
else
  echo "Info: [${GHCR}] 未提供 GHCR_USERNAME/GHCR_PASSWORD,匿名拉取(公開映像可行,可能被限流)"
fi

# 同步迴圈：逐檔最多試 MAX_ATTEMPTS 次，仍失敗就記下、續跑下一檔。
# skopeo 自己另有 --retry-times 對每顆重試；外層重跑的單位是整個規則檔，不是單顆映像。
# find 的結果經 sort，每晚的處理順序與失敗清單順序固定。
# 用行程替換餵 find 的結果，failed 才留在主 shell；管線的 while 跑在子 shell，迴圈後讀不到。
# 叢集端的規則檔由 ConfigMap 掛載，卷根每個檔都是指向 ..data/<檔> 的 symlink：
# -L 讓 -type f 認得 symlink，-maxdepth 1 擋掉 ..data 與時間戳目錄底下的同名檔，否則每檔會跑三次。
# 迴圈內的 sudo 與 skopeo 可能讀 stdin，find 的結果改走檔案描述子 3。
MAX_ATTEMPTS=3
failed=()
while read -r -u 3 yaml; do
  image="$(basename -s .yaml "${yaml}")"
  for attempt in $(seq 1 "${MAX_ATTEMPTS}"); do
    if sudo skopeo sync --src yaml --dest docker "${yaml}" "${DEST}${image}" --keep-going --retry-times 5; then
      break
    fi
    if [[ "${attempt}" -eq "${MAX_ATTEMPTS}" ]]; then
      echo "Info: [skip] ${image} failed after ${MAX_ATTEMPTS} attempts, moving on"
      failed+=("${image}")
      break
    fi
    echo "Info: [retry] ${image} attempt ${attempt} failed, retrying in 30s..."
    sleep 30
  done
done 3< <(find -L "${here}/../repository" -maxdepth 1 -type f -name "${YAML_REGEX}" | sort)

if [[ "${#failed[@]}" -gt 0 ]]; then
  echo "Error: 下列映像同步失敗（各已試 ${MAX_ATTEMPTS} 次）：" >&2
  printf '  %s\n' "${failed[@]}" >&2
  exit 1
fi
echo "Success: 全部映像同步完成"
