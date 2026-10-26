#!/bin/bash
# img.sh 單元測試
# 用法:bash tests/test_img.sh
# 失敗時 exit 1
#
# 機制:
#   PATH 前置 fixtures/stubs/ → sudo/podman 被替換為 log-only stub
#   FAMILIES_ROOT 指向 fixtures/img/ → img.sh 看到 fake family
#   每個 case 清 PODMAN_LOG,跑 img.sh,grep log + 看 exit code
# 注意:test runner 不用 set -e,因為部分 case 預期 img.sh 回非零(用 check_exit 驗)
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
img="${repo_root}/infra/bin/img.sh"
stubs="${repo_root}/tests/fixtures/stubs"
img_fixtures="${repo_root}/tests/fixtures/img"
log_file="/tmp/test_img_podman.log"

pass=0
fail=0

# 重設 log，清 env，設 PATH 與 fixture root
setup_test() {
    : > "${log_file}"
    unset FAIL_ON_TAG TEST_FAIL_SVC
    export PATH="${stubs}:${PATH}"
    export PODMAN_LOG="${log_file}"
    export FAMILIES_ROOT="${img_fixtures}"
    # 假前綴，避免 stub 記錄的 tag 污染真實 registry 命名空間
    export REGISTRY_PREFIX="test.local/x"
    # build_args() 的全域注入需 config/versions.conf（供讀取 PROVISION_REF）；以此 fixture 隔離，不依賴真 repo 那份
    export ROOT_VERSIONS="${img_fixtures%/img}/root-versions.conf"
    # push/pull/exists 認證:用 env 假憑證(ensure_login 只讀 env,不碰任何檔)
    export QUAY_USERNAME="u" QUAY_PASSWORD="p"
}

# 還原(每個 case 末段呼叫,避免污染下一個 case)
teardown_test() {
    export PATH="${PATH#${stubs}:}"
    unset PODMAN_LOG FAMILIES_ROOT REGISTRY_PREFIX ROOT_VERSIONS FAIL_ON_TAG TEST_FAIL_SVC QUAY_USERNAME QUAY_PASSWORD INSPECT_FAIL_TAG
}

# 驗 log 內某模式出現次數
check_log_count() {
    local name="${1}" pattern="${2}" expected="${3}"
    local actual
    # grep -c 找不到也會輸出 "0" + exit 1;不能再 || echo 0(會雙輸出)
    # -e 是必要的:斷言 --build-arg 這類 pattern 時,開頭的 -- 會被 grep 當旗標
    actual="$(grep -cE -e "${pattern}" "${log_file}" 2>/dev/null)"
    actual="${actual:-0}"
    if [[ "${actual}" -eq "${expected}" ]]; then
        echo "[OK] ${name} (${pattern} × ${actual})"
        pass=$((pass+1))
    else
        echo "[FAIL] ${name}: expected ${expected} matches of '${pattern}', got ${actual}" >&2
        echo "       log content:" >&2
        sed 's/^/         /' "${log_file}" >&2
        fail=$((fail+1))
    fi
}

# 驗 log 中兩個 pattern 的出現順序(第一個必須在第二個之前)
check_log_order() {
    local name="${1}" first="${2}" second="${3}"
    local line_first line_second
    line_first="$(grep -nE "${first}" "${log_file}" | head -1 | cut -d: -f1 || echo 0)"
    line_second="$(grep -nE "${second}" "${log_file}" | head -1 | cut -d: -f1 || echo 0)"
    if [[ "${line_first}" -gt 0 && "${line_second}" -gt 0 && "${line_first}" -lt "${line_second}" ]]; then
        echo "[OK] ${name} (${first} @${line_first} before ${second} @${line_second})"
        pass=$((pass+1))
    else
        echo "[FAIL] ${name}: '${first}' @${line_first} not before '${second}' @${line_second}" >&2
        fail=$((fail+1))
    fi
}

# 驗「log 裡 build 的 service 順序」＝「fixture conf 宣告的 CHAIN 順序」。
# 期望值自 conf 推導,不硬編:硬編會讓 fixture 與斷言各自漂移;首尾兩點比對
# (舊 check_log_order 的用法)則抓不到中段亂序,也抓不到整條被 sort 掉——
# fixture 的 CHAIN 若恰為字母序,加 | sort 的突變會存活。
check_log_sequence() {
    local name="${1}" family="${2}"
    local expected actual
    expected="$(sed -n 's/^CHAIN="\(.*\)"$/\1/p' "${img_fixtures}/${family}/versions.conf" | tr ' ' '\n')"
    # 自 podman build 命令列的 -t 參數取 service 名(tag 形如 <family>:<svc>-<ver>)
    actual="$(sed -nE "s|^podman build .* -t [^ ]*/${family}:([^-]+)-.*|\1|p" "${log_file}")"
    if [[ "${expected}" == "${actual}" && -n "${actual}" ]]; then
        echo "[OK] ${name} (build 序＝CHAIN 序 $(printf '%s' "${actual}" | tr '\n' ' '))"
        pass=$((pass+1))
    else
        echo "[FAIL] ${name}: build 序與 CHAIN 序不符" >&2
        echo "       期望(conf CHAIN): $(printf '%s' "${expected}" | tr '\n' ' ')" >&2
        echo "       實際(build log):  $(printf '%s' "${actual}" | tr '\n' ' ')" >&2
        fail=$((fail+1))
    fi
}

# 驗 exit code
check_exit() {
    local name="${1}" expected="${2}" actual="${3}"
    if [[ "${actual}" -eq "${expected}" ]]; then
        echo "[OK] ${name} (exit ${actual})"
        pass=$((pass+1))
    else
        echo "[FAIL] ${name}: expected exit ${expected}, got ${actual}" >&2
        fail=$((fail+1))
    fi
}

# 驗 stderr 含字串
check_stderr_contains() {
    local name="${1}" pattern="${2}" stderr_file="${3}"
    if grep -qE "${pattern}" "${stderr_file}"; then
        echo "[OK] ${name} (stderr contains '${pattern}')"
        pass=$((pass+1))
    else
        echo "[FAIL] ${name}: stderr missing '${pattern}'" >&2
        echo "       stderr content:" >&2
        sed 's/^/         /' "${stderr_file}" >&2
        fail=$((fail+1))
    fi
}

# 驗任意檔內 pattern 出現次數(泛化 check_log_count 到 stdout 捕獲檔)
check_count_in() {
    local name="${1}" file="${2}" pattern="${3}" expected="${4}"
    local actual
    # grep -c 找不到也會輸出 "0" + exit 1;不能再 || echo 0(會雙輸出)
    actual="$(grep -cE -e "${pattern}" "${file}" 2>/dev/null)"
    actual="${actual:-0}"
    if [[ "${actual}" -eq "${expected}" ]]; then
        echo "[OK] ${name} (${pattern} × ${actual})"
        pass=$((pass+1))
    else
        echo "[FAIL] ${name}: expected ${expected} of '${pattern}' in ${file}, got ${actual}" >&2
        fail=$((fail+1))
    fi
}

# ===== Case 1: build chain5 走完 5 個(FD 3 regression) =====
setup_test
bash "${img}" build chain5 >/dev/null 2>&1
rc=$?
check_exit "case 1 build chain5 exit 0" 0 "${rc}"
check_log_count "case 1 build chain5 ran 5 builds" '^podman build' 5
check_log_count "case 1 builds use docker format (SHELL/pipefail 需 docker 格式)" '^podman build --format docker' 5
check_log_count "case 1 Containerfile 由 -f <path> 指定" '^podman build --format docker -f .*/chain5/s[1-5]\.Dockerfile ' 5
check_log_count "case 1 五顆各自指向自己的 Dockerfile" '^podman build --format docker -f .*/s[1-5]\.Dockerfile -t ' 5
check_log_sequence "case 1 build chain5 順序＝CHAIN 宣告序(非字母序)" chain5
teardown_test

# ===== Case 2: ci chain5 全 pass → rmi 全 5 =====
setup_test
bash "${img}" ci chain5 >/dev/null 2>&1
rc=$?
check_exit "case 2 ci chain5 exit 0" 0 "${rc}"
check_log_count "case 2 ci chain5 ran 5 builds" '^podman build' 5
check_log_count "case 2 ci chain5 ran 5 rmis" '^podman rmi' 5
teardown_test

# ===== Case 3: ci chain5 第 3 svc build 失敗 → 不 rmi =====
# 目標取 CHAIN 第 3 位的 s1(CHAIN="s3 s5 s1 s4 s2");s1 在字母序是第 1 位,
# 所以本 case 的「恰好 3 次 build」同時擋住 chain 被 sort 掉的退化。
setup_test
export FAIL_ON_TAG="s1-v0.0.1"
err_file="$(mktemp)"
bash "${img}" ci chain5 >/dev/null 2>"${err_file}"
rc=$?
check_exit "case 3 ci chain5 build-fail exit non-zero" 1 "${rc}"
check_log_count "case 3 ci chain5 attempted 3 builds (stops at CHAIN 第 3 位 s1)" '^podman build' 3
check_log_count "case 3 ci chain5 no rmi (preserves images for debug)" '^podman rmi' 0
check_stderr_contains "case 3 ci chain5 reports build failure" 'build failed' "${err_file}"
rm "${err_file}"
teardown_test

# ===== Case 4: ci chain5 第 3 svc test 失敗 → 不 rmi =====
setup_test
export TEST_FAIL_SVC="s1"
err_file="$(mktemp)"
bash "${img}" ci chain5 >/dev/null 2>"${err_file}"
rc=$?
check_exit "case 4 ci chain5 test-fail exit non-zero" 1 "${rc}"
check_log_count "case 4 ci chain5 built 3 (CHAIN 第 3 位 s1 build OK, test fails)" '^podman build' 3
check_log_count "case 4 ci chain5 no rmi" '^podman rmi' 0
check_stderr_contains "case 4 ci chain5 reports test failure" 'test failed' "${err_file}"
rm "${err_file}"
teardown_test

# ===== Case 5: ci taroko matrix 全 build+rmi 交錯 =====
# fixture 三軸的值互不重疊(NODES=v1.x／SERVERS_CRI_DOCKER=v2.x／SERVERS_DOCKER=v3.x),
# 所以下面逐格斷言抓得到「某一軸的餵料鍵接錯」——三軸共用同一組值時,
# 把 node 迴圈改讀 SERVERS_CRI_DOCKER 產出的 tag 集合完全相同,斷言全部照過。
setup_test
bash "${img}" ci taroko >/dev/null 2>&1
rc=$?
check_exit "case 5 ci taroko exit 0" 0 "${rc}"
check_log_count "case 5 ci taroko ran 5 builds" '^podman build' 5
check_log_count "case 5 ci taroko ran 5 rmis" '^podman rmi' 5
# node 兩格:值只在 NODES 出現,cri-docker／docker 軸取不到
check_log_count "case 5 node 第 1 格 taroko:v1.1.1 (1 build + 1 rmi)" 'taroko:v1\.1\.1( |$)' 2
check_log_count "case 5 node 第 2 格 taroko:v1.1.2 (1 build + 1 rmi)" 'taroko:v1\.1\.2( |$)' 2
check_log_count "case 5 node 迴圈只吃 NODES(不含 v2/v3 軸的值)" 'taroko:v[23]\.' 0
# cri-docker 兩格
check_log_count "case 5 cri-docker 第 1 格 v2.2.1 (1 build + 1 rmi)" 'taroko:cri-docker-v2\.2\.1( |$)' 2
check_log_count "case 5 cri-docker 第 2 格 v2.2.2 (1 build + 1 rmi)" 'taroko:cri-docker-v2\.2\.2( |$)' 2
# docker 一格
check_log_count "case 5 docker 格 v3.3.3 (1 build + 1 rmi)" 'taroko:docker-v3\.3\.3( |$)' 2
# KUBERNETES_VERSION 只能由 NODES 餵,值域必須落在 v1.x
check_log_count "case 5 KUBERNETES_VERSION 兩次且皆取自 NODES" '--build-arg KUBERNETES_VERSION=v1\.1\.[12]' 2
check_log_count "case 5 KEY_VERSION 兩次且皆取自 SERVERS_CRI_DOCKER" '--build-arg KEY_VERSION=v2\.2\.[12]' 2
teardown_test

# ===== Case 6: img.sh 無 args → exit 1 + usage =====
setup_test
err_file="$(mktemp)"
bash "${img}" >/dev/null 2>"${err_file}"
rc=$?
check_exit "case 6 img.sh no args exit 1" 1 "${rc}"
check_stderr_contains "case 6 img.sh no args prints usage" 'usage: img\.sh' "${err_file}"
rm "${err_file}"
teardown_test

# ===== Case 7: img.sh foo → exit 1 + Error =====
setup_test
err_file="$(mktemp)"
bash "${img}" foo >/dev/null 2>"${err_file}"
rc=$?
check_exit "case 7 img.sh unknown cmd exit 1" 1 "${rc}"
check_stderr_contains "case 7 img.sh unknown cmd reports error" "Error: unknown command 'foo'" "${err_file}"
rm "${err_file}"
teardown_test

# ===== Case 8: push chain5 → ensure_login 1×skopeo login + 5×podman push =====
setup_test
bash "${img}" push chain5 >/dev/null 2>&1
rc=$?
check_exit "case 8 push chain5 exit 0" 0 "${rc}"
check_log_count "case 8 push chain5 login once" '^skopeo login test\.local' 1
check_log_count "case 8 login 走 --password-stdin" 'skopeo login test\.local -u u --password-stdin' 1
check_log_count "case 8 密碼不落 argv" ' -p ' 0
check_log_count "case 8 push chain5 pushed 5" '^podman push .*chain5:s[1-5]-v0\.0\.1' 5
teardown_test

# ===== Case 9: push chain5 s3 → 單顆 =====
setup_test
bash "${img}" push chain5 s3 >/dev/null 2>&1
rc=$?
check_exit "case 9 push chain5 s3 exit 0" 0 "${rc}"
check_log_count "case 9 push single s3" '^podman push .*chain5:s3-v0\.0\.1' 1
check_log_count "case 9 push single only 1" '^podman push' 1
teardown_test

# ===== Case 10: push taroko → matrix 全 5 =====
setup_test
bash "${img}" push taroko >/dev/null 2>&1
rc=$?
check_exit "case 10 push taroko exit 0" 0 "${rc}"
check_log_count "case 10 push taroko matrix 5" '^podman push .*taroko:' 5
teardown_test

# ===== Case 11: push taroko <service> → fail-loud =====
setup_test
err_file="$(mktemp)"
bash "${img}" push taroko node >/dev/null 2>"${err_file}"
rc=$?
check_exit "case 11 push taroko node exit 1" 1 "${rc}"
check_stderr_contains "case 11 taroko single rejected" '不支援單 service' "${err_file}"
rm "${err_file}"
teardown_test

# ===== Case 12: push 缺憑證 → fail-fast =====
setup_test
unset QUAY_USERNAME
err_file="$(mktemp)"
bash "${img}" push chain5 >/dev/null 2>"${err_file}"
rc=$?
check_exit "case 12 push no-cred exit non-zero" 1 "${rc}"
rm "${err_file}"
teardown_test

# ===== Case 13: pull chain5 → 5×podman pull =====
setup_test
bash "${img}" pull chain5 >/dev/null 2>&1
rc=$?
check_exit "case 13 pull chain5 exit 0" 0 "${rc}"
check_log_count "case 13 pull chain5 pulled 5" '^podman pull .*chain5:s[1-5]-v0\.0\.1' 5
teardown_test

# ===== Case 14: pull chain5 s2 → 單顆 =====
setup_test
bash "${img}" pull chain5 s2 >/dev/null 2>&1
rc=$?
check_exit "case 14 pull chain5 s2 exit 0" 0 "${rc}"
check_log_count "case 14 pull single s2" '^podman pull .*chain5:s2-v0\.0\.1' 1
check_log_count "case 14 pull single only 1" '^podman pull' 1
teardown_test

# ===== Case 15: exists chain5 全存在 → exit 0 + 5×skopeo inspect =====
setup_test
bash "${img}" exists chain5 >/dev/null 2>&1
rc=$?
check_exit "case 15 exists chain5 all present exit 0" 0 "${rc}"
check_log_count "case 15 exists chain5 inspected 5" '^skopeo inspect docker://.*chain5:s[1-5]-v0\.0\.1' 5
teardown_test

# ===== Case 16: exists chain5 缺 s3 → exit≠0 + MISSING =====
setup_test
export INSPECT_FAIL_TAG="chain5:s3-v0.0.1"
err_file="$(mktemp)"
bash "${img}" exists chain5 >/dev/null 2>"${err_file}"
rc=$?
check_exit "case 16 exists missing s3 exit 1" 1 "${rc}"
check_stderr_contains "case 16 reports MISSING s3" 'MISSING: .*chain5:s3-v0\.0\.1' "${err_file}"
rm "${err_file}"
teardown_test

# ===== Case 17: build taroko <service> → reject(taroko matrix,無單 service) =====
setup_test
err_file="$(mktemp)"
bash "${img}" build taroko node >/dev/null 2>"${err_file}"
rc=$?
check_exit "case 17 build taroko node exit 1" 1 "${rc}"
check_log_count "case 17 build taroko node no build" '^podman build' 0
check_stderr_contains "case 17 taroko single rejected" '不支援單 service' "${err_file}"
rm "${err_file}"
teardown_test

# ===== Case 18: build <family> KEY=VAL → reject(KEY=VAL 誤入 service 位) =====
setup_test
err_file="$(mktemp)"
bash "${img}" build chain5 FOO=bar >/dev/null 2>"${err_file}"
rc=$?
check_exit "case 18 build chain5 FOO=bar exit 1" 1 "${rc}"
check_log_count "case 18 no build" '^podman build' 0
check_stderr_contains "case 18 KEY=VAL rejected" 'KEY=VAL' "${err_file}"
rm "${err_file}"
teardown_test

# ===== Case 19: ci <family> KEY=VAL → reject =====
setup_test
err_file="$(mktemp)"
bash "${img}" ci chain5 FOO=bar >/dev/null 2>"${err_file}"
rc=$?
check_exit "case 19 ci chain5 FOO=bar exit 1" 1 "${rc}"
check_log_count "case 19 no build" '^podman build' 0
check_stderr_contains "case 19 KEY=VAL rejected" 'KEY=VAL' "${err_file}"
rm "${err_file}"
teardown_test

# ===== Case 20: 已退役的 render 子命令不得復活(渲染結果即 Dockerfile 本身) =====
setup_test
err_file="$(mktemp)"
bash "${img}" render chain5 s1 >/dev/null 2>"${err_file}"
rc=$?
check_exit "case 20 render 子命令已退役 exit 1" 1 "${rc}"
check_stderr_contains "case 20 報 unknown command" "unknown command 'render'" "${err_file}"
rm "${err_file}"
teardown_test

# ===== Case 21: build <family> KEY=VAL(KEY=VAL 誤入 service 位)→ reject =====
setup_test
err_file="$(mktemp)"
bash "${img}" build chain5 BASE=x >/dev/null 2>"${err_file}"
rc=$?
check_exit "case 21 build chain5 BASE=x exit 1" 1 "${rc}"
check_stderr_contains "case 21 build KEY=VAL rejected" 'KEY=VAL' "${err_file}"
rm "${err_file}"
teardown_test

# ===== Case 22: dev chain5(family-only)→ 5 build + 5 test, 0 rmi(全保留) =====
setup_test
out_file="$(mktemp)"
bash "${img}" dev chain5 >"${out_file}" 2>&1
rc=$?
check_exit "case 22 dev chain5 exit 0" 0 "${rc}"
check_log_count "case 22 dev chain5 built 5" '^podman build' 5
check_log_count "case 22 dev chain5 no rmi (保留)" '^podman rmi' 0
check_count_in "case 22 dev chain5 tested 5" "${out_file}" '\[FAKE TESTFILE OK\]' 5
rm "${out_file}"
teardown_test

# ===== Case 23: dev chain5 s3(單顆)→ 1 build + 1 test, 0 rmi =====
setup_test
out_file="$(mktemp)"
bash "${img}" dev chain5 s3 >"${out_file}" 2>&1
rc=$?
check_exit "case 23 dev chain5 s3 exit 0" 0 "${rc}"
check_log_count "case 23 built 1" '^podman build' 1
check_log_count "case 23 no rmi" '^podman rmi' 0
check_count_in "case 23 tested s3" "${out_file}" '\[FAKE TESTFILE OK\] chain5:s3-v0\.0\.1' 1
rm "${out_file}"
teardown_test

# ===== Case 24: dev taroko(family-only)→ build_taroko(5 build,0 rmi)+ Info 略過 test =====
setup_test
out_file="$(mktemp)"
bash "${img}" dev taroko >"${out_file}" 2>&1
rc=$?
check_exit "case 24 dev taroko exit 0" 0 "${rc}"
check_log_count "case 24 dev taroko built 5 (matrix)" '^podman build' 5
check_log_count "case 24 dev taroko no rmi (保留)" '^podman rmi' 0
check_count_in "case 24 dev taroko notes no-testfile" "${out_file}" 'taroko 無 testfile' 1
rm "${out_file}"
teardown_test

# ===== Case 25: dev taroko node → reject(taroko matrix) =====
setup_test
err_file="$(mktemp)"
bash "${img}" dev taroko node >/dev/null 2>"${err_file}"
rc=$?
check_exit "case 25 dev taroko node exit 1" 1 "${rc}"
check_log_count "case 25 no build" '^podman build' 0
check_stderr_contains "case 25 taroko single rejected" '不支援單 service' "${err_file}"
rm "${err_file}"
teardown_test

# ===== Case 26: dev chain5 KEY=VAL(誤入 service 位)→ reject =====
setup_test
err_file="$(mktemp)"
bash "${img}" dev chain5 FOO=bar >/dev/null 2>"${err_file}"
rc=$?
check_exit "case 26 dev chain5 FOO=bar exit 1" 1 "${rc}"
check_log_count "case 26 no build" '^podman build' 0
check_stderr_contains "case 26 KEY=VAL rejected" 'KEY=VAL' "${err_file}"
rm "${err_file}"
teardown_test

# ===== Case 27: test chain5(family-only)→ 5 test, 0 build, 0 rmi =====
setup_test
out_file="$(mktemp)"
bash "${img}" test chain5 >"${out_file}" 2>&1
rc=$?
check_exit "case 27 test chain5 exit 0" 0 "${rc}"
check_log_count "case 27 test chain5 no build" '^podman build' 0
check_count_in "case 27 test chain5 tested 5" "${out_file}" '\[FAKE TESTFILE OK\]' 5
rm "${out_file}"
teardown_test

# ===== Case 28: test taroko(family-only)→ Info 略過, exit 0, 0 test =====
setup_test
out_file="$(mktemp)"
bash "${img}" test taroko >"${out_file}" 2>&1
rc=$?
check_exit "case 28 test taroko exit 0" 0 "${rc}"
check_log_count "case 28 test taroko no build" '^podman build' 0
check_count_in "case 28 test taroko skip note" "${out_file}" 'taroko 無 testfile' 1
rm "${out_file}"
teardown_test

# ===== Case 29: test taroko node → reject =====
setup_test
err_file="$(mktemp)"
bash "${img}" test taroko node >/dev/null 2>"${err_file}"
rc=$?
check_exit "case 29 test taroko node exit 1" 1 "${rc}"
check_stderr_contains "case 29 taroko single rejected" '不支援單 service' "${err_file}"
rm "${err_file}"
teardown_test

# ===== Case 30: 非 repo 根 cwd 組值表(輸入側 cwd 迴歸) =====
# 不用 fixtures:清掉 FAMILIES_ROOT 等 env 遮蔽,驗 img.sh 以絕對路徑解析 conf 與 Dockerfile；alpine 已遷到 imgctl，改用 ubuntu 的 base
setup_test
unset FAMILIES_ROOT ROOT_VERSIONS REGISTRY_PREFIX
out="$( (cd /tmp && bash "${img}" __dump_build_args ubuntu base) 2>&1 )"
rc=$?
check_exit "case 30 非 repo 根 cwd 組值表 exit 0" 0 "${rc}"
if [[ "${out}" == *"REGISTRY_PREFIX="* && "${out}" == *"PROVISION_REF_IN="* ]]; then
    echo "[OK] case 30 值表含全域鍵與 config/versions.conf 衍生鍵"
    pass=$((pass+1))
else
    echo "[FAIL] case 30 值表內容不對: ${out}" >&2
    fail=$((fail+1))
fi
teardown_test

# ===== Case 31: family conf 缺 SERVICE_VERSION → 報錯,不組 <svc>-null tag =====
setup_test
export FAMILIES_ROOT="${repo_root}/tests/fixtures/badimg"
stderr_file="/tmp/test_img_case31.stderr"
bash "${img}" build noversion >/dev/null 2>"${stderr_file}"
rc=$?
check_exit "case 31 缺 SERVICE_VERSION build 非零" 1 "${rc}"
check_stderr_contains "case 31 錯誤訊息點名 SERVICE_VERSION" 'SERVICE_VERSION' "${stderr_file}"
check_log_count "case 31 未組出 null tag 也未 build" '^podman build' 0
rm -f "${stderr_file}"
teardown_test

# ===== Case 32: manifest 用 fixtures 走完(FAMILIES+MANIFEST_OUT 覆寫) =====
setup_test
export FAMILIES="chain5 taroko"
export MANIFEST_OUT="/tmp/test_img_manifest.yaml"
bash "${img}" manifest >/dev/null 2>&1
rc=$?
check_exit "case 32 manifest exit 0" 0 "${rc}"
# 反向引用 \1 要求鍵與值的 service 名相同:寫成 s[1-5]: s[1-5] 時,
# 「s3: s5-v0.0.1」這種錯配也會命中,五條全錯照樣數到 5
check_count_in "case 32 chain5 五 service 各自對到自己的 sN-v0.0.1" "${MANIFEST_OUT}" 's([1-5]): s\1-v0\.0\.1' 5
check_count_in "case 32 taroko matrix 三行" "${MANIFEST_OUT}" '^    (nodes|cri-docker|docker): \[' 3
rm -f "${MANIFEST_OUT}"
unset FAMILIES MANIFEST_OUT
teardown_test

# ===== Case 33: FAMILIES 集合與目錄不一致 → families_check 擋下 =====
setup_test
export FAMILIES="chain5"
stderr_file="/tmp/test_img_case33.stderr"
bash "${img}" manifest >/dev/null 2>"${stderr_file}"
rc=$?
check_exit "case 33 清單缺 taroko manifest 非零" 1 "${rc}"
check_stderr_contains "case 33 錯誤訊息點名不一致" '不一致' "${stderr_file}"
rm -f "${stderr_file}"
unset FAMILIES
teardown_test

# ===== Case 34: manifest --check 綠(剛生成+全部 tag 線上) =====
setup_test
export FAMILIES="chain5 taroko"
export MANIFEST_OUT="/tmp/test_img_manifest_check.yaml"
bash "${img}" manifest >/dev/null 2>&1
bash "${img}" manifest --check >/dev/null 2>&1
rc=$?
check_exit "case 34 manifest --check exit 0" 0 "${rc}"
check_log_count "case 34 逐 ref inspect(chain5 5+taroko 5)" '^skopeo inspect' 10
rm -f "${MANIFEST_OUT}"
unset FAMILIES MANIFEST_OUT
teardown_test

# ===== Case 35: manifest 過期 → --check 擋下 =====
setup_test
export FAMILIES="chain5 taroko"
export MANIFEST_OUT="/tmp/test_img_manifest_check.yaml"
bash "${img}" manifest >/dev/null 2>&1
echo "# 模擬過期:多一行" >> "${MANIFEST_OUT}"
stderr_file="/tmp/test_img_case35.stderr"
bash "${img}" manifest --check >/dev/null 2>"${stderr_file}"
rc=$?
check_exit "case 35 過期 manifest 非零" 1 "${rc}"
check_stderr_contains "case 35 錯誤訊息點名過期" '過期' "${stderr_file}"
rm -f "${MANIFEST_OUT}" "${stderr_file}"
unset FAMILIES MANIFEST_OUT
teardown_test

# ===== Case 36: manifest 承諾的 tag 缺線上 → --check 擋下 =====
setup_test
export FAMILIES="chain5 taroko"
export MANIFEST_OUT="/tmp/test_img_manifest_check.yaml"
bash "${img}" manifest >/dev/null 2>&1
export INSPECT_FAIL_TAG="s3-v0.0.1"
bash "${img}" manifest --check >/dev/null 2>&1
rc=$?
check_exit "case 36 缺 tag 非零" 1 "${rc}"
rm -f "${MANIFEST_OUT}"
unset FAMILIES MANIFEST_OUT INSPECT_FAIL_TAG
teardown_test

echo

# ===== Case 37: CLI 覆寫對別名鍵(ARG_ALIAS)生效 =====
# 迴歸:查表若無條件走別名,CLI 對 PROVISION_REF_IN 的覆寫會被換回 PROVISION_REF 的值而失效。
# 用真 repo(不用 fixtures):別名表綁在 img.sh,需要真的 ubuntu/knife.Dockerfile 有該光桿 ARG。
setup_test
unset FAMILIES_ROOT ROOT_VERSIONS REGISTRY_PREFIX
out="$( (cd "${repo_root}" && bash "${img}" __dump_build_args ubuntu knife PROVISION_REF_IN=v9.9.9-probe) 2>&1 )"
if printf '%s' "${out}" | grep -q 'PROVISION_REF_IN=v9.9.9-probe'; then
    echo "[OK] case 37 CLI 覆寫對別名鍵生效"
    pass=$((pass+1))
else
    echo "[FAIL] case 37 CLI 覆寫被別名解析吃掉: ${out}" >&2
    fail=$((fail+1))
fi
out="$( (cd "${repo_root}" && bash "${img}" __dump_build_args ubuntu knife) 2>&1 )"
if printf '%s' "${out}" | grep -q 'PROVISION_REF_IN=v'; then
    echo "[OK] case 37 無覆寫時仍走別名取 config/versions.conf 的值"
    pass=$((pass+1))
else
    echo "[FAIL] case 37 別名解析失效: ${out}" >&2
    fail=$((fail+1))
fi
teardown_test

# ===== Case 38: 不存在的 family 名在 build／dev／test 必須 fail-loud =====
# 迴歸:這三條直接進 family_services_in_chain() 的 process substitution 迴圈,
# conf_get 在 subshell 裡 source 失敗的 rc 被丟棄,零次迭代後走成功路徑 → rc=0 的假成功。
# ci 靠入口的 family_service_version() 本來就擋得住,列為對照組。
for sub in build dev test ci; do
    setup_test
    err_file="$(mktemp)"
    bash "${img}" "${sub}" nosuchfamily >/dev/null 2>"${err_file}"
    rc=$?
    check_exit "case 38 ${sub} nosuchfamily exit 非零" 1 "${rc}"
    check_log_count "case 38 ${sub} nosuchfamily 未觸發任何 build" '^podman build' 0
    check_stderr_contains "case 38 ${sub} nosuchfamily 錯誤訊息點名 versions.conf" 'versions\.conf' "${err_file}"
    rm "${err_file}"
    teardown_test
done

# ===== Case 39: 存在的 family 不受守衛誤殺(反向保險) =====
# require_family 若把判準寫成目錄存在或誤用相對路徑,正常路徑會一起壞掉;
# 這條確保守衛只擋不存在的 family。
setup_test
bash "${img}" build chain5 >/dev/null 2>&1
check_exit "case 39 守衛不誤殺存在的 family" 0 "$?"
check_log_count "case 39 chain5 仍照建 5 顆" '^podman build' 5
teardown_test


# ===== Case 40: CRLF 化的 config/versions.conf 不讓值尾殘留 \r =====
# build_args() 第 2 層以 sed 取 PROVISION_REF 後接 `tr -d '\r'`,此前零覆蓋。
# bash 側的讀取沒有 universal newlines 這種東西(Python 那邊有),\r 會真的留在值裡,
# 組進 raw/${PROVISION_REF}/ 的 URL 就壞掉,而 curl 的錯誤訊息看不出多了個 CR。
# fixture 在執行期生成:.gitattributes 的 `versions.conf text eol=lf` 會把
# committed 的 CRLF 檔正規化掉,存成檔案驗不到。
# 用真 repo 的 ubuntu/knife(同 case 37 的理由):PROVISION_REF_IN 是 ARG_ALIAS 的鍵,
# 需要真的有宣告該光桿 ARG 的 Dockerfile,fixture 的 taroko/node 只宣告 KUBERNETES_VERSION。
setup_test
unset FAMILIES_ROOT REGISTRY_PREFIX
crlf_root="$(mktemp -d)"
printf 'IMAGES_REF=v0.0.0\r\nPROVISION_REF=v7.7.7\r\n' > "${crlf_root}/versions.conf"
export ROOT_VERSIONS="${crlf_root}/versions.conf"
out="$( (cd "${repo_root}" && bash "${img}" __dump_build_args ubuntu knife) 2>&1 )"
rc=$?
check_exit "case 40 CRLF 的 config/versions.conf 仍組得出值表" 0 "${rc}"
# 輸出的是 ARG 名 PROVISION_REF_IN(經 ARG_ALIAS 對回 conf 的 PROVISION_REF),不是 conf 鍵名。
# 用 $ 錨定行尾:殘留的 \r 會落在 v7.7.7 之後,讓 'v7\.7\.7$' 失配
if printf '%s\n' "${out}" | grep -qE 'PROVISION_REF_IN=v7\.7\.7$'; then
    echo "[OK] case 40 PROVISION_REF 值尾無殘留 CR"
    pass=$((pass+1))
else
    echo "[FAIL] case 40 PROVISION_REF 值尾疑有 CR 殘留: $(printf '%s' "${out}" | tr -d '\n' | cat -v)" >&2
    fail=$((fail+1))
fi
rm -rf "${crlf_root}"
teardown_test

echo "${pass} passed, ${fail} failed"
[[ "${fail}" -eq 0 ]]
