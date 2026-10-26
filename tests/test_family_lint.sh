#!/bin/bash
# family-lint.py 單元測試(專驗 conf schema 文法、FROM 拓撲、ARG 契約四條)
# 用法:bash tests/test_family_lint.sh
# 不設 -e:壞 fixture 預期回非零 rc,靠下方 rc=$? 親自捕捉;補 -e 會讓腳本在第一個 expected_rc 非 0 的測試就中止,整批失效
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lint="${repo_root}/bin/family-lint.py"
fx="${repo_root}/tests/fixtures/lint"

pass=0
fail=0

# 驗 rc 與 stderr 關鍵字;expected_rc=0 時 keyword 留空
check_lint() {
    local name="${1}" yaml="${2}" expected_rc="${3}" keyword="${4:-}"
    local stderr_file="/tmp/test_family_lint.stderr"
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

check_lint "goodfam 拓撲全過(跳過行不誤報)" "${fx}/goodfam/versions.conf" 0
check_lint "badorder 引用後位 service 擋下" "${fx}/badorder/versions.conf" 1 "順序"
check_lint "badupstream 未宣告跨家族擋下" "${fx}/badupstream/versions.conf" 1 "UPSTREAM"
check_lint "badmissing 引用不存在 service 擋下" "${fx}/badmissing/versions.conf" 1 "不在 CHAIN"

# conf schema:本檔會被 source,文法違規等同可執行程式碼,這幾條的位階等同機密掃描
check_lint "含空白的值未加引號擋下" "${fx}/unquoted/versions.conf" 1 "未加雙引號"
check_lint "值含命令替換擋下" "${fx}/inject/versions.conf" 1 "命令替換"
check_lint "小寫鍵名擋下" "${fx}/badkey/versions.conf" 1 "KEY=value"
# 過度嚴格的反向保險:引號內的 & | ; 是純字面,source 安全,不得誤殺
check_lint "引號內的 shell metachar 放行" "${fx}/quotedmeta/versions.conf" 0

# ARG 契約四條(取代已退役的 @{} 作用域規則)
check_lint "① 光桿 ARG 不在值表擋下" "${fx}/badarg/versions.conf" 1 "不在值表"
check_lint "② 跨 stage 未重宣告擋下" "${fx}/badscope/versions.conf" 1 "未宣告 ARG"
check_lint "② 續行上的未宣告用點也擋下" "${fx}/badcont/versions.conf" 1 "未宣告 ARG"
check_lint "③ 同名光桿 ARG 與 ENV 並存擋下" "${fx}/badenv/versions.conf" 1 "同名並存"

# conf 文法的其餘負向分支。上面四條 schema 檢查只覆蓋了 parse_conf() 的一部分,
# 這批把剩下的 fail() 出口補齊——它們全都會讓 source 的結果與肉眼所見不同。
check_lint "重複鍵擋下(source 時後者靜默勝出)" "${fx}/dupkey/versions.conf" 1 "重複鍵"
check_lint "雙引號未閉合擋下(會吃掉後續行)" "${fx}/unclosed/versions.conf" 1 "未閉合"
check_lint "值內含未跳脫雙引號擋下" "${fx}/innerquote/versions.conf" 1 "未跳脫"
check_lint "非空白類 metachar 未加引號擋下(| 是 pipeline)" "${fx}/metachar/versions.conf" 1 "metachar"
check_lint "全註解檔擋下(無有效宣告)" "${fx}/emptyconf/versions.conf" 1 "無有效宣告"
check_lint "缺檔擋下(不靜默當成合法)" "${fx}/nosuchdir/versions.conf" 1 "不存在"

# 非-matrix 的 schema 兩條
check_lint "SERVICE_VERSION 非 vX.Y.Z 擋下" "${fx}/badver/versions.conf" 1 "vX.Y.Z"
check_lint "CHAIN 空擋下(build 會零次迭代)" "${fx}/emptychain/versions.conf" 1 "CHAIN 須為非空"

# matrix 形態:此前這一整條分支(含合法路徑)零覆蓋,而 taroko 是 repo 內唯一的 matrix family
check_lint "matrix 合法形態放行" "${fx}/goodmatrix/versions.conf" 0
check_lint "matrix 誤帶 CHAIN 擋下(兩形態互斥)" "${fx}/mtxchain/versions.conf" 1 "不得有 SERVICE_VERSION"
check_lint "matrix 空 NODES 擋下" "${fx}/mtxnonodes/versions.conf" 1 "非空 NODES"
check_lint "matrix 缺 SERVERS_* 擋下" "${fx}/mtxnoservers/versions.conf" 1 "SERVERS_"

# 規則自身的失效偵測:正則寫死字面時整條 FROM 拓撲規則會靜默關閉,
# 自我檢查(有候選卻零匹配)是唯一擋得住的東西,它本身也需要一個 fixture
check_lint "FROM 拓撲規則零匹配但有候選 → 擋下" "${fx}/fromselfcheck/versions.conf" 1 "脫節"

# 過渡期:infra/<family>/.imgctl 空標記＝該 family 已遷移到 imgctl。
# 跳過 Dockerfile 規則（FROM 拓撲、①到④），versions.conf 文法照驗。
# 這裡驗 stdout 的 Info，所以不用 check_lint（它丟掉 stdout）。
stdout_file="/tmp/test_family_lint.stdout"
python3 "${lint}" "${fx}/imgctlskip/versions.conf" >"${stdout_file}" 2>/dev/null
rc=$?
if [[ "${rc}" -eq 0 ]] && grep -q "已遷移到 imgctl" "${stdout_file}"; then
    echo "[OK] .imgctl 標記跳過 Dockerfile 規則並印 Info"
    pass=$((pass+1))
else
    echo "[FAIL] .imgctl 標記:expected rc 0 + Info, got rc ${rc}" >&2
    sed 's/^/       /' "${stdout_file}" >&2
    fail=$((fail+1))
fi
rm -f "${stdout_file}"
check_lint ".imgctl 標記的 family 仍驗 conf 文法(未加引號擋下)" "${fx}/imgctlbad/versions.conf" 1 "未加雙引號"

# 無參數:usage 出口
stderr_file="/tmp/test_family_lint.stderr"
python3 "${lint}" >/dev/null 2>"${stderr_file}"
rc=$?
if [[ "${rc}" -eq 1 ]] && grep -q "用法" "${stderr_file}"; then
    echo "[OK] 無參數印 usage 並回非零"
    pass=$((pass+1))
else
    echo "[FAIL] 無參數:expected rc 1 + usage, got rc ${rc}" >&2
    sed 's/^/       /' "${stderr_file}" >&2
    fail=$((fail+1))
fi
rm -f "${stderr_file}"

# CRLF:此前零覆蓋。fixture 不能用 committed 檔——.gitattributes 的
# `versions.conf text eol=lf` 會在 checkout 時把 CRLF 正規化掉,測試會變成什麼都沒驗。
# 故在執行期生成。CRLF 化的 conf 若讓值尾留下 \r,SERVICE_VERSION 就不符 vX.Y.Z、
# CHAIN 的最後一個 service 名會組出 <svc>\r-<ver> 的壞 tag。
crlf_dir="$(mktemp -d)"
printf 'SERVICE_VERSION=v0.0.1\r\nCHAIN="a b"\r\n' > "${crlf_dir}/versions.conf"
check_lint "CRLF 化的 conf 仍正確解析(值尾不留 \\r)" "${crlf_dir}/versions.conf" 0
# 單獨的 CR:Python 的 universal newlines 把它當換行,所以後半段變成獨立一行、
# 撞上「不是 KEY=value」。重點是 fail-loud 而非靜默取到半截值。
printf 'SERVICE_VERSION=v0.0.1\rBOGUS\nCHAIN=a\n' > "${crlf_dir}/versions.conf"
check_lint "單獨的 CR 不靜默吞掉(fail-loud)" "${crlf_dir}/versions.conf" 1 "不是 KEY=value"
rm -rf "${crlf_dir}"

# 多檔逐一驗:任一失敗即整體非零(main() 的迴圈語意;單檔全過時不得誤判)
check_lint_multi() {
    local name="${1}" expected_rc="${2}"; shift 2
    local stderr_file="/tmp/test_family_lint.stderr"
    python3 "${lint}" "$@" >/dev/null 2>"${stderr_file}"
    local rc=$?
    if [[ "${rc}" -eq "${expected_rc}" ]]; then
        echo "[OK] ${name}"
        pass=$((pass+1))
    else
        echo "[FAIL] ${name}: expected rc ${expected_rc}, got ${rc}" >&2
        sed 's/^/       /' "${stderr_file}" >&2
        fail=$((fail+1))
    fi
    rm -f "${stderr_file}"
}
check_lint_multi "多檔全合法 → rc 0" 0 "${fx}/goodfam/versions.conf" "${fx}/goodmatrix/versions.conf"
check_lint_multi "多檔中有一個壞的 → rc 非零" 1 "${fx}/goodfam/versions.conf" "${fx}/badver/versions.conf"

echo "${pass} passed, ${fail} failed"
[[ "${fail}" -eq 0 ]]
