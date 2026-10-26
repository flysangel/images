#!/bin/bash
# test_sync_start.sh — sync/bin/start.sh 的結束碼、失敗清單與規則檔走訪次數
# 註記：逐項容錯，捨棄 -e；被測腳本預期回非零，靠 rc=$? 親自捕捉
# 用法：bash tests/test_sync_start.sh
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
start_sh="${repo_root}/sync/bin/start.sh"
stubs="${repo_root}/tests/fixtures/stubs"

# stub 沒有 exec bit 時 PATH 前置無效，start.sh 會打到真的 sudo skopeo、實際登入並同步，先擋下
for stub in sudo skopeo; do
  [[ -x "${stubs}/${stub}" ]] || { echo "Error: ${stubs}/${stub} 沒有 exec bit，會打到真的 ${stub}" >&2; exit 1; }
done

pass=0
fail=0
ok()  { echo "[OK] ${1}"; pass=$((pass+1)); }
bad() { echo "[FAIL] ${1}" >&2; fail=$((fail+1)); }

tmp_root="$(mktemp -d)"
trap 'rm -rf "${tmp_root}"' EXIT
log_file="${tmp_root}/skopeo.log"
out_file="${tmp_root}/out"
err_file="${tmp_root}/err"

# start.sh 每次重試前 sleep 30；用空的 sleep 蓋掉，失敗案例才不會一顆等一分鐘
mkdir -p "${tmp_root}/nosleep"
printf '#!/bin/bash\nexit 0\n' > "${tmp_root}/nosleep/sleep"
chmod +x "${tmp_root}/nosleep/sleep"

# 模擬 ConfigMap 掛載：卷根的每個檔都是指向 ..data/<檔> 的 symlink，
# ..data 再指向帶時間戳的實體目錄。start.sh 自己也是這樣掛進 bin/。
mount_configmap() {
  local dir="$1"
  shift
  local stamp="..2026_09_27_00_00_00.000000000"
  local src
  mkdir -p "${dir}/${stamp}"
  for src in "$@"; do
    cp "${src}" "${dir}/${stamp}/"
    ln -s "..data/$(basename "${src}")" "${dir}/$(basename "${src}")"
  done
  ln -s "${stamp}" "${dir}/..data"
}

rules_src="${tmp_root}/rules"
mkdir -p "${rules_src}"
printf 'docker.io:\n  images-by-tag-regex:\n    library/alpha: ^1$\n' > "${rules_src}/alpha.yaml"
printf 'quay.io:\n  images-by-tag-regex:\n    org/beta: ^1$\n' > "${rules_src}/beta.yaml"
printf 'docker.io:\n  images-by-tag-regex:\n    library/gamma: ^1$\n' > "${rules_src}/gamma.yaml"

cm_root="${tmp_root}/opt/sync"
mount_configmap "${cm_root}/bin" "${start_sh}"
mount_configmap "${cm_root}/repository" "${rules_src}"/*.yaml
cm_start="${cm_root}/bin/start.sh"

# 跑一次 start.sh；額外的 env（SYNC_FAIL_IMAGE、LOGIN_FAIL_HOST）由呼叫端以指令前綴帶入
run_start() {
  : > "${log_file}"
  PATH="${tmp_root}/nosleep:${stubs}:${PATH}" PODMAN_LOG="${log_file}" \
    DOCKER_USERNAME=u DOCKER_PASSWORD=p REDHAT_USERNAME=u REDHAT_PASSWORD=p \
    QUAY_USERNAME=u QUAY_PASSWORD=p \
    bash "$1" >"${out_file}" 2>"${err_file}"
}

# 某映像在 log 裡被 skopeo sync 的次數
sync_count() {
  grep -c "^skopeo sync .* quay.io/flysangel/$1 " "${log_file}"
}

# 一、真 sync/repository（一般檔）全部成功：rc=0，每個規則檔剛好同步一次
run_start "${start_sh}"
rc=$?
if [[ "${rc}" -eq 0 ]]; then
  ok "全部成功 rc=0"
else
  bad "全部成功卻 rc=${rc}"
  sed 's/^/       /' "${err_file}" >&2
fi
want="$(ls "${repo_root}"/sync/repository/*.yaml | wc -l)"
got="$(grep -c '^skopeo sync ' "${log_file}")"
if [[ "${got}" -eq "${want}" ]]; then
  ok "一般檔結構下每個規則檔同步一次（${got} 次）"
else
  bad "一般檔結構下同步 ${got} 次，規則檔有 ${want} 個"
fi
if grep -q '^Success: ' "${out_file}"; then
  ok "全部成功印 Success:"
else
  bad "全部成功卻沒印 Success:"
fi

# 二、ConfigMap 的 symlink 結構：每個規則檔只處理一次，..data 與時間戳目錄不重複撈
run_start "${cm_start}"
rc=$?
counts="$(sync_count alpha) $(sync_count beta) $(sync_count gamma)"
if [[ "${rc}" -eq 0 && "${counts}" == "1 1 1" ]]; then
  ok "symlink 結構下每個規則檔只處理一次"
else
  bad "symlink 結構下 rc=${rc}，alpha／beta／gamma 各同步 ${counts} 次（應為 1 1 1）"
fi

# 三、有失敗：rc=1，stderr 列出失敗映像，其餘照跑
SYNC_FAIL_IMAGE=beta run_start "${cm_start}"
rc=$?
if [[ "${rc}" -eq 1 ]]; then
  ok "有映像失敗 rc=1"
else
  bad "有映像失敗卻 rc=${rc}"
fi
if grep -q '^Error: ' "${err_file}" && grep -qx '  beta' "${err_file}"; then
  ok "stderr 以 Error: 開頭並列出失敗映像 beta"
else
  bad "stderr 沒有 Error: 或沒列出 beta"
  sed 's/^/       /' "${err_file}" >&2
fi
if ! grep -qx '  alpha' "${err_file}" && ! grep -qx '  gamma' "${err_file}"; then
  ok "成功的映像不在失敗清單"
else
  bad "失敗清單混進成功的映像"
fi
counts="$(sync_count alpha) $(sync_count beta) $(sync_count gamma)"
if [[ "${counts}" == "1 3 1" ]]; then
  ok "失敗映像重試到上限，其餘各一次"
else
  bad "alpha／beta／gamma 各同步 ${counts} 次（應為 1 3 1）"
fi

# 四、某 registry 登入失敗：不中止，該 registry 的映像同步失敗會被計入，其餘照跑
LOGIN_FAIL_HOST=quay.io run_start "${cm_start}"
rc=$?
if [[ "${rc}" -eq 1 ]] && grep -qx '  beta' "${err_file}"; then
  ok "登入失敗的 registry 其同步失敗被計入（rc=1，列出 beta）"
else
  bad "登入 quay.io 失敗後 rc=${rc}，失敗清單沒有 beta"
  sed 's/^/       /' "${err_file}" >&2
fi
counts="$(sync_count alpha) $(sync_count gamma)"
if [[ "${counts}" == "1 1" ]]; then
  ok "登入失敗不中止其他 registry 的同步"
else
  bad "登入失敗後 alpha／gamma 各同步 ${counts} 次（應為 1 1）"
fi

echo "${pass} passed, ${fail} failed"
[[ "${fail}" -eq 0 ]]
