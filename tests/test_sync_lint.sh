#!/bin/bash
# sync-lint.py 單元測試(驗 sync/repository/*.yaml 的規則 schema 五條 + 檔名 + 白名單推導)
# 用法:bash tests/test_sync_lint.sh
# 不設 -e:壞 fixture 預期回非零 rc,靠下方 rc=$? 親自捕捉
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lint="${repo_root}/bin/sync-lint.py"
fx="${repo_root}/tests/fixtures/sync"
# 白名單自 start.sh 推導,測試沿用真檔(它就是被驗的契約來源)
export SYNC_START_SH="${repo_root}/sync/bin/start.sh"

pass=0
fail=0

check_lint() {
    local name="${1}" yaml="${2}" expected_rc="${3}" keyword="${4:-}"
    local stderr_file="/tmp/test_sync_lint.stderr"
    python3 "${lint}" "${yaml}" >/dev/null 2>"${stderr_file}"
    local rc=$?
    if [[ "${rc}" -ne "${expected_rc}" ]]; then
        echo "[FAIL] ${name}: expected rc ${expected_rc}, got ${rc}" >&2
        sed 's/^/       /' "${stderr_file}" >&2
        fail=$((fail+1)); rm -f "${stderr_file}"; return
    fi
    if [[ -n "${keyword}" ]] && ! grep -q "${keyword}" "${stderr_file}"; then
        echo "[FAIL] ${name}: stderr missing '${keyword}'" >&2
        sed 's/^/       /' "${stderr_file}" >&2
        fail=$((fail+1)); rm -f "${stderr_file}"; return
    fi
    echo "[OK] ${name}"
    pass=$((pass+1)); rm -f "${stderr_file}"
}

check_lint "正向 fixture 放行"                    "${fx}/good.yaml"       0
check_lint "YAML 文法壞掉擋下"                    "${fx}/badyaml.yaml"    1 "YAML 解析失敗"
check_lint "頂層非 mapping 擋下"                  "${fx}/notmapping.yaml" 1 "非空 mapping"
check_lint "start.sh 不登入的主機擋下"            "${fx}/badhost.yaml"    1 "不在 start.sh"
check_lint "主機的值是 null 擋下(忘了規則表)"     "${fx}/nullhostbody.yaml" 1 "的值須為非空 mapping"
check_lint "非預期的第二層鍵擋下"                 "${fx}/badkey.yaml"     1 "非預期鍵"
check_lint "空規則表擋下(等於什麼都不同步)"       "${fx}/emptytable.yaml" 1 "images-by-tag-regex 須為非空"
check_lint "image 名非 ns/name 形狀擋下"          "${fx}/badimage.yaml"   1 "形狀"
check_lint "tag regex 是 null 擋下(忘了 regex)"    "${fx}/nullregex.yaml"  1 "須為非空字串"
check_lint "tag regex 無法編譯擋下"               "${fx}/badregex.yaml"   1 "無法編譯"
check_lint "檔名非合法 path 段擋下"               "${fx}/Bad_Name.yaml"   1 "registry path 段"
check_lint "缺檔擋下(不靜默當合法)"               "${fx}/nosuch.yaml"     1 "不存在"

# 副檔名不是 .yaml:start.sh 的 find 只收 *.yaml,收了別的等於規則檔沒在跑
tmp_bad_ext="$(mktemp -d)/rules.yml"
cp "${fx}/good.yaml" "${tmp_bad_ext}"
check_lint "副檔名非 .yaml 擋下"                  "${tmp_bad_ext}"        1 "副檔名"
rm -rf "$(dirname "${tmp_bad_ext}")"

# 白名單推導自身的失效偵測:HOST_DEFAULT_RE 與 start.sh 寫法脫節時,
# 白名單會變成空集合 → 所有主機都被判非法(或反過來全部放行)。這條驗它 fail-loud。
stderr_file="/tmp/test_sync_lint.stderr"
empty_start="$(mktemp)"
printf '#!/bin/bash\n# 沒有任何 ${VAR:=host} 形態的預設值賦值\n' > "${empty_start}"
SYNC_START_SH="${empty_start}" python3 "${lint}" "${fx}/good.yaml" >/dev/null 2>"${stderr_file}"
rc=$?
if [[ "${rc}" -eq 1 ]] && grep -q "脫節" "${stderr_file}"; then
    echo "[OK] 白名單推導取不到主機時 fail-loud(不靜默放行)"
    pass=$((pass+1))
else
    echo "[FAIL] 白名單推導失效未被偵測:rc=${rc}" >&2
    sed 's/^/       /' "${stderr_file}" >&2
    fail=$((fail+1))
fi
rm -f "${empty_start}"

SYNC_START_SH="/nonexistent/start.sh" python3 "${lint}" "${fx}/good.yaml" >/dev/null 2>"${stderr_file}"
rc=$?
if [[ "${rc}" -eq 1 ]] && grep -q "不存在" "${stderr_file}"; then
    echo "[OK] 白名單來源缺檔時 fail-loud"
    pass=$((pass+1))
else
    echo "[FAIL] 白名單來源缺檔未 fail-loud:rc=${rc}" >&2
    fail=$((fail+1))
fi
rm -f "${stderr_file}"

# 預設白名單來源以 sync-lint.py 自己的位置推 repo 根，不靠工作目錄
if (cd /tmp && env -u SYNC_START_SH python3 "${lint}" "${fx}/good.yaml") >/dev/null 2>"${stderr_file}"; then
  echo "[OK] 非 repo 根 cwd、未設 SYNC_START_SH 仍找得到 start.sh"
  pass=$((pass+1))
else
  echo "[FAIL] 非 repo 根 cwd 找不到 start.sh" >&2
  sed 's/^/       /' "${stderr_file}" >&2
  fail=$((fail+1))
fi
rm -f "${stderr_file}"

# 無參數:usage 出口
stderr_file="/tmp/test_sync_lint.stderr"
python3 "${lint}" >/dev/null 2>"${stderr_file}"
rc=$?
if [[ "${rc}" -eq 1 ]] && grep -q "用法" "${stderr_file}"; then
    echo "[OK] 無參數印 usage 並回非零"
    pass=$((pass+1))
else
    echo "[FAIL] 無參數:expected rc 1 + usage, got rc ${rc}" >&2
    fail=$((fail+1))
fi
rm -f "${stderr_file}"

# 真產物:30 個規則檔必須全過(這支 lint 存在的理由就是守它們)
python3 "${lint}" "${repo_root}"/sync/repository/*.yaml >/dev/null 2>"/tmp/test_sync_lint.stderr"
rc=$?
n="$(ls "${repo_root}"/sync/repository/*.yaml | wc -l)"
if [[ "${rc}" -eq 0 ]]; then
    echo "[OK] 真 sync/repository 全過(${n} 檔)"
    pass=$((pass+1))
else
    echo "[FAIL] 真 sync/repository 有檔不合規" >&2
    sed 's/^/       /' "/tmp/test_sync_lint.stderr" >&2
    fail=$((fail+1))
fi
rm -f "/tmp/test_sync_lint.stderr"

echo "${pass} passed, ${fail} failed"
[[ "${fail}" -eq 0 ]]
