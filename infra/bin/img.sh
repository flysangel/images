#!/bin/bash
# img.sh — build / test orchestrator(讀 versions.conf 組 --build-arg + sudo podman)
# 用法:
#   img.sh build  <family>                           build 整 family,依 CHAIN 順序(保留 image)
#   img.sh build  <family> <service>                 build 單一(保留 image)
#   img.sh dev    <family>                           build + test 整 chain(保留)
#   img.sh dev    <family> <service> [KEY=VAL ...]   build + test 單一(保留,主開發迴圈)
#   img.sh build-all                                 全 repo build(保留 image)
#   img.sh test   <family>                           整 chain 逐顆跑 testfile
#   img.sh test   <family> <service>                 對 ${REGISTRY_PREFIX}/<family>:<service>-<ver> 跑 testfile
#   img.sh test-all
#   註:build/dev/ci/test 帶 service 時 taroko 一律報錯(matrix,無單 service);service 位不可為 KEY=VAL。
#   img.sh ci     <family> <service> [KEY=VAL ...]   build + test + rmi(單一)
#   img.sh ci     <family>                           整 family:依 CHAIN build+test 全成功才 rmi 全部
#                                                    (中途失敗保留 image 給 debug;taroko 走 matrix
#                                                    每個 build 完即 rmi)
#   img.sh ci-all                                    全 repo ci
#   img.sh manifest                                  由各 family 的 versions.conf 衍生 docs/images-manifest.yaml
#   img.sh manifest --check                          發版守門:manifest 與 versions.conf 一致+全部 tag 線上存在
#   img.sh push   <family> [service]                 已建好的 image push 上 registry(單顆或整 family)
#   img.sh pull   <family> [service]                 從 registry 拉 image(單顆或整 family)
#   img.sh exists <family> [service]                 skopeo inspect 線上存在性斷言(任一缺 → 非零)
#   img.sh rmi    <family> [service]                 移除本機已建 image(單顆或整 family)
#   img.sh __dump_build_args <family> <service> [KEY=VAL ...]
#                                                    印該顆的 --build-arg 值表(debug;取代已退役的 render 子命令)
# 只設 pipefail 不設 -e：各函式以 return 1 配呼叫端 exit 1 處理失敗，ci_family 失敗時要保留映像並印已建數量，-e 會跳過那段
set -o pipefail

lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${lib_dir}/../.." && pwd)"
infra_root="${FAMILIES_ROOT:-${repo_root}/infra}"
# export 讓 testfile 子程序與本檔用同一 infra 根(FAMILIES_ROOT 覆寫情境也一致)
export FAMILIES_ROOT="${infra_root}"

# build_args() 由此讀 PROVISION_REF;export 供 testfile 子程序與測試覆寫。
ROOT_VERSIONS="${ROOT_VERSIONS:-${repo_root}/config/versions.conf}"
export ROOT_VERSIONS
REGISTRY_PREFIX="${REGISTRY_PREFIX:-quay.io/flysangel}"
# testfile 子程序在執行期用 "${REGISTRY_PREFIX}/${img_tag}" 拼映像參考
export REGISTRY_PREFIX

# 順序即跨 family FROM 依賴的拓撲序(ubuntu 先於 bigdata/rdp、alpine 先於 fbs/gmm/taroko/open-webui/landlord、
# bigdata 先於 landlord),不得改字母序,否則 build 拉不到上游映像。新增 family 要同時建目錄並加進這裡。
# FAMILIES env 覆寫供測試以 fixtures 跑 manifest/-all 路徑。
read -r -a FAMILIES_DEFAULT <<< "${FAMILIES:-alpine ubuntu bigdata fbs open-webui rdp gmm taroko landlord}"

# 讀某 family conf 的單一鍵;subshell 隔離,避免 SERVICE_VERSION 等鍵撞名污染呼叫端
# shellcheck source=/dev/null
conf_get() { ( . "${infra_root}/${1}/versions.conf"; printf '%s\n' "${!2-}" ); }

# 契約 ARG 名 ← conf 鍵名(Dockerfile 側的 ARG 名與 conf 鍵不同名時)。
# PROVISION_REF_IN:避開父映像繼承的 ENV PROVISION_REF 蓋掉同名光桿 ARG——實測父映像有
#   ENV X 時,子映像的 ARG X 加 --build-arg X=新值 會被靜默忽略,${X} 取到的是父映像的舊值。
# *_VERSION ← *_DIR:bigdata 沿用既有樣板慣例,值是解壓後的目錄名。
# 與 bin/family-lint.py 的 ARG_ALIAS 同一份語意,改一邊要改兩邊。
declare -A ARG_ALIAS=(
  [PROVISION_REF_IN]=PROVISION_REF
  [JAVA_VERSION]=JAVA_DIR
  [ZOOKEEPER_VERSION]=ZOOKEEPER_DIR
  [KAFKA_VERSION]=KAFKA_DIR
  [HADOOP_VERSION]=HADOOP_DIR
  [HBASE_VERSION]=HBASE_DIR
  [HIVE_VERSION]=HIVE_DIR
  [SPARK_VERSION]=SPARK_DIR
)

# 列出某 Dockerfile 宣告的光桿 ARG(無預設值)＝契約鍵。帶預設值的 ARG 是 Dockerfile 自有,不在此列。
dockerfile_contract_args() {
  sed -nE 's/^[[:space:]]*ARG[[:space:]]+([A-Z][A-Z0-9_]*)[[:space:]]*$/\1/p' "${1}" | sort -u
}

# 組 --build-arg:每行一個(旗標與 KEY=VAL 分行),呼叫端 mapfile -t 接。
# 值表優先序（低→高）：內建全域 → config/versions.conf 的 PROVISION_REF → upstream 衍生 → 本 family conf → CLI 覆寫。
# 只傳該 Dockerfile 宣告過的光桿 ARG(避開 podman 對「供了未宣告」的 warning);缺鍵即 fail-fast。
build_args() {
  local family="${1}" service="${2}"; shift 2
  local df="${infra_root}/${family}/${service}.Dockerfile"
  [[ -f "${df}" ]] || { echo "Error: ${df} not found" >&2; return 1; }
  local -A vals
  # 1) 內建全域
  vals[REGISTRY_PREFIX]="${REGISTRY_PREFIX}"
  vals[UPSTREAM_DOCKER]="docker.io"
  # 2) config/versions.conf 的 PROVISION_REF（嚴格文法讓取值退化成前綴剝除，不需解析器）
  local gpref
  gpref="$(sed -n 's/^PROVISION_REF=//p' "${ROOT_VERSIONS}" | head -1 | tr -d '\r')"
  [[ -n "${gpref}" ]] && vals[PROVISION_REF]="${gpref}"
  # 3) upstream 衍生:加 family 名前綴
  local up up_upper up_v
  for up in $(conf_get "${family}" UPSTREAM); do
    up_upper="$(echo "${up}" | tr '[:lower:]-' '[:upper:]_')"
    up_v="$(conf_get "${up}" SERVICE_VERSION)"; [[ -n "${up_v}" ]] && vals["${up_upper}_SERVICE_VERSION"]="${up_v}"
    up_v="$(conf_get "${up}" BASE)";            [[ -n "${up_v}" ]] && vals["${up_upper}_BASE"]="${up_v}"
  done
  # 4) 本 family conf 全鍵(單次 subshell,不逐鍵 fork)
  local k v
  # shellcheck source=/dev/null
  while IFS='=' read -r k v; do
    [[ -z "${k}" ]] && continue
    vals["${k}"]="${v}"
  done < <( . "${infra_root}/${family}/versions.conf"
            while read -r kk; do printf '%s=%s\n' "${kk}" "${!kk-}"; done \
              < <(sed -nE 's/^([A-Z][A-Z0-9_]*)=.*/\1/p' "${infra_root}/${family}/versions.conf") )
  # 5) CLI 覆寫(優先級最高)
  local arg key
  for arg in "$@"; do
    [[ "${arg}" == *"="* ]] || { echo "Error: bad arg '${arg}', expected KEY=VAL" >&2; return 1; }
    key="${arg%%=*}"
    [[ "${key}" =~ ^[A-Z][A-Z0-9_]*$ ]] || { echo "Error: bad arg '${arg}', KEY must match [A-Z][A-Z0-9_]*" >&2; return 1; }
    vals["${key}"]="${arg#*=}"
  done
  # 交集:只傳該 Dockerfile 宣告過的光桿 ARG。
  # 查表順序:先看有沒有同名的值(CLI 覆寫會以 ARG 名直接設進值表),沒有才走別名。
  # 反過來寫的話,CLI 對別名鍵的覆寫(如 PROVISION_REF_IN=x)會被別名解析換回 source 鍵的值而失效。
  local name src
  while read -r name; do
    [[ -z "${name}" ]] && continue
    if [[ -n "${vals[${name}]+x}" ]]; then src="${name}"; else src="${ARG_ALIAS[${name}]:-${name}}"; fi
    [[ -n "${vals[${src}]+x}" ]] || {
      echo "Error: ${family}/${service}.Dockerfile 宣告了光桿 ARG ${name},但值表無 ${src}(檢查 infra/${family}/versions.conf)" >&2
      return 1
    }
    printf '%s\n%s=%s\n' "--build-arg" "${name}" "${vals[${src}]}"
  done < <(dockerfile_contract_args "${df}")
}

# 從 family conf 取 SERVICE_VERSION;缺鍵即錯(chain 家族必有,缺=資料壞,不得組出 <svc>-null tag)
family_service_version() {
  local v
  v="$(conf_get "${1}" SERVICE_VERSION)"
  [[ -n "${v}" ]] || { echo "Error: ${1}/versions.conf 缺 SERVICE_VERSION" >&2; return 1; }
  printf '%s\n' "${v}"
}

# 取 family 的 CHAIN(一維空白分隔),每行印一個 service 名;順序即 build 依賴序
family_services_in_chain() {
  conf_get "${1}" CHAIN | tr ' ' '\n'
}

# 清單集合須等於 infra/*/versions.conf 目錄集合(雙向攔:建目錄忘註冊、註冊了沒目錄)。
# 只掛清單消費入口(build-all/test-all/ci-all/manifest);單家族命令不受清單一致性綁架。
families_check() {
  local expected actual
  expected="$(printf '%s\n' "${FAMILIES_DEFAULT[@]}" | sort)"
  actual="$(for y in "${infra_root}"/*/versions.conf; do basename "$(dirname "${y}")"; done | sort)"
  [[ "${expected}" == "${actual}" ]] || {
    echo "Error: FAMILIES_DEFAULT 與 infra/*/versions.conf 目錄不一致" >&2
    diff <(printf '%s\n' "${expected}") <(printf '%s\n' "${actual}") >&2 || true
    return 1
  }
}

# 已遷移到 imgctl 的 family（infra/<family>/.imgctl 標記）由 imgctl 與 CI 處理，
# 舊的 *-all 迴圈要略過，否則 img.sh 會對它們走舊流程。回 0 表示已遷移，呼叫端 continue。
family_migrated() {
  [[ -f "${infra_root}/${1}/.imgctl" ]] || return 1
  echo "Info: ${1} 已遷移到 imgctl，略過"
}

# family 存在性守衛。build_family／dev_family／test_family 直接進
# family_services_in_chain() 的 process substitution 迴圈,conf_get 在 subshell 裡
# source 失敗的 rc 被丟棄,零次迭代後照走成功路徑——打錯 family 名會拿到 rc=0 的假成功。
# ci_family 不需要:它入口先呼叫 family_service_version(),已 fail-loud。
# 單顆路徑(build_one／test_one／dev_one)也不需要:同樣先過 family_service_version()。
require_family() {
  [[ -f "${infra_root}/${1}/versions.conf" ]] || {
    echo "Error: ${infra_root}/${1}/versions.conf 不存在(family 名打錯?)" >&2
    return 1
  }
}

# matrix 家族判準:conf 有 NODES 或任一 SERVERS_* 鍵(與 bin/family-lint.py 的 is_matrix 同源同義)。
# conf 不存在時 grep 失敗→false,走非-matrix 路徑報既有錯誤。
family_is_matrix() {
  local f="${infra_root}/${1}/versions.conf"
  [[ -f "${f}" ]] || return 1
  grep -qE '^(NODES|SERVERS_[A-Z0-9_]+)=' "${f}"
}

# 統一建置入口:走 docker 格式。模板用 SHELL ["/bin/bash","-o","pipefail","-c"] 取 pipefail,
# 但 SHELL 只在 docker 格式生效;podman 預設 OCI 會忽略 SHELL 並「靜默丟掉 pipefail」(RUN 內 pipe 失敗不中止)。
# 注意:BUILDAH_FORMAT env 沒用——build 走 sudo,env 會被 reset;必須用 --format 旗標(穿得過 sudo)。
pbuild() { sudo podman build --format docker "$@"; }

# 對單一 service: 組 build_args + pbuild
build_one() {
  local family="${1}" service="${2}"
  shift 2
  local tag_ver
  tag_ver="$(family_service_version "${family}")" || return 1
  local ba_out; local -a ba=()
  # command substitution 保住 build_args 的 rc(mapfile 吃不到 subshell 的 rc);
  # 產出為空是合法情境——完全不用契約值的 Dockerfile(如 FROM scratch)沒有光桿 ARG。
  ba_out="$(build_args "${family}" "${service}" "$@")" || return 1
  [[ -n "${ba_out}" ]] && mapfile -t ba <<< "${ba_out}"
  pbuild -f "${infra_root}/${family}/${service}.Dockerfile" "${ba[@]}" -t "${REGISTRY_PREFIX}/${family}:${service}-${tag_ver}" "${infra_root}/${family}" || return 1
}

build_family() {
  local family="${1}"
  require_family "${family}" || return 1
  if family_is_matrix "${family}"; then
    build_taroko
    return
  fi
  # 用 FD 3 餵 chain,避免內層 podman/testfile/ssh 等指令吃掉 loop 的 stdin
  while read -r -u 3 svc; do
    [[ -z "${svc}" ]] && continue
    echo "Info: [build] ${family}/${svc}"
    build_one "${family}" "${svc}" || { echo "Error: build failed at ${family}/${svc}" >&2; return 1; }
  done 3< <(family_services_in_chain "${family}")
}

# taroko: matrix 迭代 NODES / SERVERS_CRI_DOCKER / SERVERS_DOCKER
# 所有 while loop 用 FD 3 餵 conf 取值結果,避免 podman 吃掉 stdin 造成提早結束
build_taroko() {
  # node: 每個 kubernetes 版本獨立 build,tag = taroko:<kubernetes>
  while read -r -u 3 kver; do
    [[ -z "${kver}" ]] && continue
    echo "Info: [build] taroko/node KUBERNETES_VERSION=${kver}"
    local ba_out; local -a ba=()
    # command substitution 保住 build_args 的 rc(mapfile 吃不到 subshell 的 rc);
    # 產出為空是合法情境——完全不用契約值的 Dockerfile(如 FROM scratch)沒有光桿 ARG。
    ba_out="$(build_args taroko node "KUBERNETES_VERSION=${kver}")" || return 1
    [[ -n "${ba_out}" ]] && mapfile -t ba <<< "${ba_out}"
    pbuild -f "${infra_root}/taroko/node.Dockerfile" "${ba[@]}" -t "${REGISTRY_PREFIX}/taroko:${kver}" "${infra_root}/taroko" || return 1
  done 3< <(conf_get taroko NODES | tr ' ' '\n')
  # server (cri-docker): tag = taroko:cri-docker-<key>
  while read -r -u 3 key; do
    [[ -z "${key}" ]] && continue
    echo "Info: [build] taroko/server KEY_VERSION=${key}"
    local ba_out; local -a ba=()
    # command substitution 保住 build_args 的 rc(mapfile 吃不到 subshell 的 rc);
    # 產出為空是合法情境——完全不用契約值的 Dockerfile(如 FROM scratch)沒有光桿 ARG。
    ba_out="$(build_args taroko server "KEY_VERSION=${key}")" || return 1
    [[ -n "${ba_out}" ]] && mapfile -t ba <<< "${ba_out}"
    pbuild -f "${infra_root}/taroko/server.Dockerfile" "${ba[@]}" -t "${REGISTRY_PREFIX}/taroko:cri-docker-${key}" "${infra_root}/taroko" || return 1
  done 3< <(conf_get taroko SERVERS_CRI_DOCKER | tr ' ' '\n')
  # server (docker variant): tag = taroko:docker-<version>
  while read -r -u 3 ver; do
    [[ -z "${ver}" ]] && continue
    echo "Info: [build] taroko/docker version=${ver}"
    local ba_out; local -a ba=()
    # command substitution 保住 build_args 的 rc(mapfile 吃不到 subshell 的 rc);
    # 產出為空是合法情境——完全不用契約值的 Dockerfile(如 FROM scratch)沒有光桿 ARG。
    ba_out="$(build_args taroko docker)" || return 1
    [[ -n "${ba_out}" ]] && mapfile -t ba <<< "${ba_out}"
    pbuild -f "${infra_root}/taroko/docker.Dockerfile" "${ba[@]}" -t "${REGISTRY_PREFIX}/taroko:docker-${ver}" "${infra_root}/taroko" || return 1
  done 3< <(conf_get taroko SERVERS_DOCKER | tr ' ' '\n')
}

test_one() {
  local family="${1}" service="${2}"
  local tag_ver
  tag_ver="$(family_service_version "${family}")" || return 1
  local testfile="${infra_root}/${family}/${service}.testfile"
  [[ -f "${testfile}" ]] || { echo "Error: ${testfile} not found" >&2; return 1; }
  bash "${testfile}" "${family}:${service}-${tag_ver}"
}

# test 整 family:依 chain 逐顆對已建映像跑 testfile。taroko 無 testfile → 略過。
# 與 test-all 內層 loop 小重複,刻意不抽共用(對齊本檔小重複取捨)。
test_family() {
  local family="${1}"
  require_family "${family}" || return 1
  if family_is_matrix "${family}"; then
    echo "Info: [test] taroko 無 testfile,略過"
    return 0
  fi
  # FD 3 餵 chain,避免內層 testfile 的 ssh/sshpass 吃 stdin
  while read -r -u 3 svc; do
    [[ -z "${svc}" ]] && continue
    echo "Info: [test] ${family}/${svc}"
    test_one "${family}" "${svc}" || return 1
  done 3< <(family_services_in_chain "${family}")
}

# 移除指定 tag 列表(忽略不存在,不噴錯)
rmi_tags() {
  for tag in "$@"; do
    sudo podman rmi -f "${tag}" >/dev/null 2>&1 || true
  done
}

# dev：build+test，保留 image（主開發迴圈）
# = build_one(build,保留) + 跑 testfile；不 rmi。
# build+test 段與 ci_one 小重複,刻意不抽共用以保 ci(CI 關鍵路徑)零改動
# (對齊本檔對小重複的既有取捨,見 family_image_refs 上方的註解)。
dev_one() {
  local family="${1}" service="${2}"
  shift 2
  build_one "${family}" "${service}" "$@" || return 1
  local testfile="${infra_root}/${family}/${service}.testfile"
  [[ -f "${testfile}" ]] || return 0
  local tag_ver
  tag_ver="$(family_service_version "${family}")" || return 1
  echo "Info: [dev] test ${family}:${service}-${tag_ver}"
  bash "${testfile}" "${family}:${service}-${tag_ver}"
}

# dev 整 family:依 chain 逐顆 dev_one(build+test+保留),中途失敗保留已建映像供 debug。
# taroko 無 testfile → 走 build_taroko(等同 build+保留)。與 build_family 小重複,刻意不抽共用。
dev_family() {
  local family="${1}"
  require_family "${family}" || return 1
  if family_is_matrix "${family}"; then
    echo "Info: [dev] taroko 無 testfile,dev 等同 build＋保留"
    build_taroko
    return
  fi
  # FD 3 餵 chain,避免內層 podman/testfile/ssh 吃掉 loop stdin(沿用本檔紀律)
  while read -r -u 3 svc; do
    [[ -z "${svc}" ]] && continue
    echo "Info: [dev] ${family}/${svc}"
    dev_one "${family}" "${svc}" || { echo "Error: dev failed at ${family}/${svc} (映像保留供 debug)" >&2; return 1; }
  done 3< <(family_services_in_chain "${family}")
}

# 單一 service CI：build + test（若有 testfile）+ rmi
# 失敗則保留 image 給 debug(test 失敗 → 不 rmi;build 失敗 → 也不 rmi)
# 注意:呼叫者需確保 chain 上游 image 已在 podman(否則 podman build 會嘗試 pull,registry 沒有則失敗)
ci_one() {
  local family="${1}" service="${2}"
  shift 2
  local tag_ver
  tag_ver="$(family_service_version "${family}")" || return 1
  local tag="${REGISTRY_PREFIX}/${family}:${service}-${tag_ver}"
  local ba_out; local -a ba=()
  # command substitution 保住 build_args 的 rc(mapfile 吃不到 subshell 的 rc);
  # 產出為空是合法情境——完全不用契約值的 Dockerfile(如 FROM scratch)沒有光桿 ARG。
  ba_out="$(build_args "${family}" "${service}" "$@")" || return 1
  [[ -n "${ba_out}" ]] && mapfile -t ba <<< "${ba_out}"
  echo "Info: [ci] build ${tag}"
  pbuild -f "${infra_root}/${family}/${service}.Dockerfile" "${ba[@]}" -t "${tag}" "${infra_root}/${family}" || return 1
  local testfile="${infra_root}/${family}/${service}.testfile"
  if [[ -f "${testfile}" ]]; then
    echo "Info: [ci] test ${tag}"
    bash "${testfile}" "${family}:${service}-${tag_ver}" || {
      echo "Error: test failed for ${tag} (image kept for debug)" >&2
      return 1
    }
  fi
  echo "Info: [ci] rmi ${tag}"
  rmi_tags "${tag}"
}

# Family CI:依 chain build+test 全部,全成功才 rmi 全部
# 中途失敗(build 或 test)立即停止,所有已 build 的 image 都保留給 debug
ci_family() {
  local family="${1}"
  if family_is_matrix "${family}"; then
    ci_taroko
    return
  fi
  local tag_ver
  tag_ver="$(family_service_version "${family}")" || return 1
  local built_tags=()
  # 用 FD 3 餵 chain,避免內層 podman/testfile/ssh 等指令吃掉 loop 的 stdin
  while read -r -u 3 svc; do
    [[ -z "${svc}" ]] && continue
    local tag="${REGISTRY_PREFIX}/${family}:${svc}-${tag_ver}"
    echo "Info: [ci] build ${tag}"
    local ba_out; local -a ba=()
    # command substitution 保住 build_args 的 rc(mapfile 吃不到 subshell 的 rc);
    # 產出為空是合法情境——完全不用契約值的 Dockerfile(如 FROM scratch)沒有光桿 ARG。
    ba_out="$(build_args "${family}" "${svc}")" || {
      echo "Error: build_args 失敗 at ${family}/${svc} (${#built_tags[@]} prior images kept for debug)" >&2
      return 1
    }
    [[ -n "${ba_out}" ]] && mapfile -t ba <<< "${ba_out}"
    pbuild -f "${infra_root}/${family}/${svc}.Dockerfile" "${ba[@]}" -t "${tag}" "${infra_root}/${family}" || {
      echo "Error: build failed at ${family}/${svc} (${#built_tags[@]} prior images kept for debug)" >&2
      return 1
    }
    built_tags+=("${tag}")
    local testfile="${infra_root}/${family}/${svc}.testfile"
    if [[ -f "${testfile}" ]]; then
      echo "Info: [ci] test ${tag}"
      bash "${testfile}" "${family}:${svc}-${tag_ver}" || {
        echo "Error: test failed at ${family}/${svc} (${#built_tags[@]} images kept for debug)" >&2
        return 1
      }
    fi
  done 3< <(family_services_in_chain "${family}")
  echo "Info: [ci] all passed, rmi ${#built_tags[@]} images"
  rmi_tags "${built_tags[@]}"
}

# taroko CI:matrix 之間互相獨立(沒 chain dep),每個 build 完即 rmi 控磁碟峰值
# 沒有 testfile,所以「ci」實質是 build + rmi
# while loop 同樣用 FD 3 避免 podman 吃 stdin
ci_taroko() {

  while read -r -u 3 kver; do
    [[ -z "${kver}" ]] && continue
    local tag="${REGISTRY_PREFIX}/taroko:${kver}"
    echo "Info: [ci] build+rmi ${tag}"
    local ba_out; local -a ba=()
    # command substitution 保住 build_args 的 rc(mapfile 吃不到 subshell 的 rc);
    # 產出為空是合法情境——完全不用契約值的 Dockerfile(如 FROM scratch)沒有光桿 ARG。
    ba_out="$(build_args taroko node "KUBERNETES_VERSION=${kver}")" || return 1
    [[ -n "${ba_out}" ]] && mapfile -t ba <<< "${ba_out}"
    pbuild -f "${infra_root}/taroko/node.Dockerfile" "${ba[@]}" -t "${tag}" "${infra_root}/taroko" || return 1
    rmi_tags "${tag}"
  done 3< <(conf_get taroko NODES | tr ' ' '\n')
  while read -r -u 3 key; do
    [[ -z "${key}" ]] && continue
    local tag="${REGISTRY_PREFIX}/taroko:cri-docker-${key}"
    echo "Info: [ci] build+rmi ${tag}"
    local ba_out; local -a ba=()
    # command substitution 保住 build_args 的 rc(mapfile 吃不到 subshell 的 rc);
    # 產出為空是合法情境——完全不用契約值的 Dockerfile(如 FROM scratch)沒有光桿 ARG。
    ba_out="$(build_args taroko server "KEY_VERSION=${key}")" || return 1
    [[ -n "${ba_out}" ]] && mapfile -t ba <<< "${ba_out}"
    pbuild -f "${infra_root}/taroko/server.Dockerfile" "${ba[@]}" -t "${tag}" "${infra_root}/taroko" || return 1
    rmi_tags "${tag}"
  done 3< <(conf_get taroko SERVERS_CRI_DOCKER | tr ' ' '\n')
  while read -r -u 3 ver; do
    [[ -z "${ver}" ]] && continue
    local tag="${REGISTRY_PREFIX}/taroko:docker-${ver}"
    echo "Info: [ci] build+rmi ${tag}"
    local ba_out; local -a ba=()
    # command substitution 保住 build_args 的 rc(mapfile 吃不到 subshell 的 rc);
    # 產出為空是合法情境——完全不用契約值的 Dockerfile(如 FROM scratch)沒有光桿 ARG。
    ba_out="$(build_args taroko docker)" || return 1
    [[ -n "${ba_out}" ]] && mapfile -t ba <<< "${ba_out}"
    pbuild -f "${infra_root}/taroko/docker.Dockerfile" "${ba[@]}" -t "${tag}" "${infra_root}/taroko" || return 1
    rmi_tags "${tag}"
  done 3< <(conf_get taroko SERVERS_DOCKER | tr ' ' '\n')
}

# manifest: 由各 family 的 versions.conf 衍生扁平版本清單(複用既有 tag 邏輯,不另寫第二份)。
# 下游 raw/<images_ref>/docs/images-manifest.yaml 取;不含 images_ref(消費端在自己 versions.conf 記)。
cmd_manifest() {
  # MANIFEST_OUT 覆寫供測試與 dry-run;預設寫下游消費的正式路徑
  local out="${MANIFEST_OUT:-${repo_root}/docs/images-manifest.yaml}"
  mkdir -p "$(dirname "${out}")"
  {
    echo "# docs/images-manifest.yaml — 由 img.sh manifest 衍生;下游釘 images_ref 後 raw 取(本檔不含 images_ref)"
    echo "registry_prefix: ${REGISTRY_PREFIX}"
    echo "images:"
    local fam ver svc
    for fam in "${FAMILIES_DEFAULT[@]}"; do
      # matrix 家族走下方 taroko 專屬段
      family_is_matrix "${fam}" && continue
      ver="$(family_service_version "${fam}")" || return 1
      echo "  ${fam}:"
      while read -r -u 3 svc; do
        [[ -z "${svc}" ]] && continue
        echo "    ${svc}: ${svc}-${ver}"
      done 3< <(family_services_in_chain "${fam}")
    done
    # taroko 三 matrix:存完整 tag suffix(taroko: 之後的部分),與非-taroko 的 <service>-<ver> 對齊
    echo "  taroko:"
    echo "    nodes: [$(conf_get taroko NODES | tr ' ' '\n' | paste -sd, - | sed 's/,/, /g')]"
    echo "    cri-docker: [$(conf_get taroko SERVERS_CRI_DOCKER | tr ' ' '\n' | sed 's/^/cri-docker-/' | paste -sd, - | sed 's/,/, /g')]"
    echo "    docker: [$(conf_get taroko SERVERS_DOCKER | tr ' ' '\n' | sed 's/^/docker-/' | paste -sd, - | sed 's/,/, /g')]"
  } > "${out}"
  echo "Info: [manifest] wrote ${out}"
}

# 發版守門:manifest 須(1)與 versions.conf 衍生結果一致(過期即紅)(2)承諾的每個 tag 線上存在。
# 開發中間態(先 bump 未 build)跑它本來就該紅——守門語意,不塞 pre-push、不自動重生。
cmd_manifest_check() {
  local manifest="${MANIFEST_OUT:-${repo_root}/docs/images-manifest.yaml}"
  [[ -f "${manifest}" ]] || { echo "Error: ${manifest} 不存在,先跑 img.sh manifest" >&2; return 1; }
  local fresh
  fresh="$(mktemp)"
  if ! MANIFEST_OUT="${fresh}" cmd_manifest >/dev/null; then rm -f "${fresh}"; return 1; fi
  if ! diff -u "${manifest}" "${fresh}"; then
    rm -f "${fresh}"
    echo "Error: manifest 過期(與 versions.conf 衍生結果不一致);build+push 完成後跑 img.sh manifest 重生" >&2
    return 1
  fi
  rm -f "${fresh}"
  local fam rc=0
  for fam in "${FAMILIES_DEFAULT[@]}"; do
    cmd_exists "${fam}" || rc=1
  done
  [[ "${rc}" -eq 0 ]] && echo "Success: manifest 與 versions.conf 一致,全部 tag 線上存在"
  return "${rc}"
}

# 登入 registry:憑證由 task 的 dotenv(sync/secret/secret.env)或 env 提供,host 由 REGISTRY_PREFIX 導出。
# 不在此讀檔:該檔同時餵 kustomize secretGenerator,值一律裸寫,含 | 的裸值 source 會被當 pipeline。
ensure_login() {
  : "${QUAY_USERNAME:?需由 task 的 dotenv(sync/secret/secret.env)或 env 提供}"
  : "${QUAY_PASSWORD:?需由 task 的 dotenv(sync/secret/secret.env)或 env 提供}"
  # 密碼走 --password-stdin 不落 argv(防 ps 可見);host 在前保住引數順序
  printf '%s' "${QUAY_PASSWORD}" | sudo skopeo login "${REGISTRY_PREFIX%%/*}" -u "${QUAY_USERNAME}" --password-stdin
}

# 列一個 family 的全部完整 image ref(每行一個)。taroko 走 matrix、不接單 service。
# 只餵 push/pull/exists/rmi;build/ci/manifest 各自的 tag 邏輯不動。
# taroko 的 conf 取值與 build_taroko 小重複,第 5 個消費者出現再抽單一來源。
family_image_refs() {
  local family="${1}" service="${2:-}"
  if family_is_matrix "${family}"; then
    [[ -n "${service}" ]] && { echo "Error: ${family} 走 matrix,不支援單 service" >&2; return 1; }
  
    conf_get taroko NODES              | tr ' ' '\n' | while read -r k; do [[ -n "${k}" ]] && echo "${REGISTRY_PREFIX}/taroko:${k}"; done
    conf_get taroko SERVERS_CRI_DOCKER | tr ' ' '\n' | while read -r k; do [[ -n "${k}" ]] && echo "${REGISTRY_PREFIX}/taroko:cri-docker-${k}"; done
    conf_get taroko SERVERS_DOCKER     | tr ' ' '\n' | while read -r v; do [[ -n "${v}" ]] && echo "${REGISTRY_PREFIX}/taroko:docker-${v}"; done
    return 0
  fi
  local ver; ver="$(family_service_version "${family}")" || return 1
  if [[ -n "${service}" ]]; then
    echo "${REGISTRY_PREFIX}/${family}:${service}-${ver}"
  else
    family_services_in_chain "${family}" | while read -r svc; do [[ -n "${svc}" ]] && echo "${REGISTRY_PREFIX}/${family}:${svc}-${ver}"; done
  fi
}

# push:逐 ref sudo podman push。先解析 refs(taroko+service 可 fail-fast)再 login 再推。
cmd_push() {
  local family="${1:?usage: img.sh push <family> [service]}" service="${2:-}"
  local refs; refs="$(family_image_refs "${family}" "${service}")" || return 1
  ensure_login
  local ref
  # FD 3 餵 refs,避免 podman push 吃掉 loop stdin(沿用本檔 chain loop 紀律)
  while read -r -u 3 ref; do
    [[ -z "${ref}" ]] && continue
    echo "Info: [push] ${ref}"
    sudo podman push "${ref}" || { echo "Error: push failed ${ref}" >&2; return 1; }
  done 3<<< "${refs}"
}

# pull:逐 ref sudo podman pull(拉 chain 上游墊底或單顆)。
cmd_pull() {
  local family="${1:?usage: img.sh pull <family> [service]}" service="${2:-}"
  local refs; refs="$(family_image_refs "${family}" "${service}")" || return 1
  ensure_login
  local ref
  while read -r -u 3 ref; do
    [[ -z "${ref}" ]] && continue
    echo "Info: [pull] ${ref}"
    sudo podman pull "${ref}" || { echo "Error: pull failed ${ref}" >&2; return 1; }
  done 3<<< "${refs}"
}

# exists:逐 ref sudo skopeo inspect;聚合 rc(任一缺 → 非零)。
cmd_exists() {
  local family="${1:?usage: img.sh exists <family> [service]}" service="${2:-}"
  local refs; refs="$(family_image_refs "${family}" "${service}")" || return 1
  ensure_login
  local rc=0 ref
  while read -r -u 3 ref; do
    [[ -z "${ref}" ]] && continue
    if sudo skopeo inspect "docker://${ref}" >/dev/null 2>&1; then
      echo "Success: ${ref}"
    else
      echo "Error: MISSING: ${ref}" >&2; rc=1
    fi
  done 3<<< "${refs}"
  return "${rc}"
}

# rmi:移除本機已建 image(單顆或整 family)。複用 family_image_refs 解 ref、rmi_tags 忽略不存在。
cmd_rmi() {
  local family="${1:?usage: img.sh rmi <family> [service]}" service="${2:-}"
  local refs; refs="$(family_image_refs "${family}" "${service}")" || return 1
  local ref
  # FD 3 餵 refs,沿用本檔 loop 紀律
  while read -r -u 3 ref; do
    [[ -z "${ref}" ]] && continue
    echo "Info: [rmi] ${ref}"
    rmi_tags "${ref}"
  done 3<<< "${refs}"
}

# matrix 家族無單 service 概念。build/dev/ci/test 帶 service 應擋（__dump_build_args 例外：單格 debug 合法）。
reject_matrix_service() {
  family_is_matrix "${1}" && {
    echo "Error: ${1} 走 matrix,不支援單 service;要看單格的建置內容請直接讀 infra/${1}/<service>.Dockerfile 與 versions.conf" >&2
    return 1
  }
  return 0
}

# service 位長得像 KEY=VAL → 誤把 KEY=VAL build-arg 覆寫放進 service 位（整條 chain 不支援覆寫；覆寫需搭單顆）。
reject_keyval_as_service() {
  [[ "${1}" =~ ^[A-Z][A-Z0-9_]*= ]] && {
    echo "Error: '${1}' 看起來是 KEY=VAL;KEY=VAL 需搭 service,例 task build:image -- <family> <service> ${1}" >&2
    return 1
  }
  return 0
}

cmd="${1:?usage: img.sh <build|dev|build-all|test|test-all|ci|ci-all|push|pull|exists|rmi|manifest> ...}"
shift || true

case "${cmd}" in
  __dump_build_args)
    # debug 入口:印該顆的 --build-arg 值表。取代已退役的 render 子命令(渲染結果即 Dockerfile 本身)。
    build_args "${1:?usage: img.sh __dump_build_args <family> <service> [KEY=VAL ...]}" "${2:?}" "${@:3}"
    ;;
  manifest)
    families_check || exit 1
    if [[ "${1:-}" == "--check" ]]; then cmd_manifest_check; else cmd_manifest; fi
    ;;
  push)
    cmd_push "${1:?usage: img.sh push <family> [service]}" "${2:-}"
    ;;
  pull)
    cmd_pull "${1:?usage: img.sh pull <family> [service]}" "${2:-}"
    ;;
  exists)
    cmd_exists "${1:?usage: img.sh exists <family> [service]}" "${2:-}"
    ;;
  rmi)
    cmd_rmi "${1:?usage: img.sh rmi <family> [service]}" "${2:-}"
    ;;
  dev)
    family="${1:?usage: img.sh dev <family> [service]}"
    if [[ -n "${2:-}" ]]; then
      reject_matrix_service "${family}" || exit 1
      reject_keyval_as_service "${2}" || exit 1
      dev_one "${family}" "${2}" "${@:3}"
    else
      dev_family "${family}"
    fi
    ;;
  build)
    family="${1:?usage: img.sh build <family> [service]}"
    if [[ -n "${2:-}" ]]; then
      reject_matrix_service "${family}" || exit 1
      reject_keyval_as_service "${2}" || exit 1
      build_one "${family}" "${2}" "${@:3}"
    else
      build_family "${family}"
    fi
    ;;
  # *-all 逐 family 迭代，任一 family 失敗就 exit 1，後面的不跑：後面的 family 多半 FROM 前面的
  build-all)
    families_check || exit 1
    for f in "${FAMILIES_DEFAULT[@]}"; do
      family_migrated "${f}" && continue
      echo "Info: build family ${f}"
      build_family "${f}" || exit 1
    done
    ;;
  test)
    family="${1:?usage: img.sh test <family> [service]}"
    if [[ -n "${2:-}" ]]; then
      reject_matrix_service "${family}" || exit 1
      test_one "${family}" "${2}"
    else
      test_family "${family}"
    fi
    ;;
  test-all)
    families_check || exit 1
    for f in "${FAMILIES_DEFAULT[@]}"; do
      family_migrated "${f}" && continue
      # matrix 家族沒 testfile,跳過
      family_is_matrix "${f}" && continue
      # FD 3 餵 chain,避免內層 testfile 的 ssh/sshpass 吃 stdin
      while read -r -u 3 svc; do
        [[ -z "${svc}" ]] && continue
        echo "Info: [test] ${f}/${svc}"
        test_one "${f}" "${svc}" || exit 1
      done 3< <(family_services_in_chain "${f}")
    done
    ;;
  ci)
    family="${1:?usage: img.sh ci <family> [service]}"
    if [[ -n "${2:-}" ]]; then
      reject_matrix_service "${family}" || exit 1
      reject_keyval_as_service "${2}" || exit 1
      ci_one "${family}" "${2}" "${@:3}"
    else
      ci_family "${family}"
    fi
    ;;
  ci-all)
    families_check || exit 1
    for f in "${FAMILIES_DEFAULT[@]}"; do
      family_migrated "${f}" && continue
      echo "Info: ci family ${f}"
      ci_family "${f}" || exit 1
    done
    ;;
  *)
    echo "Error: unknown command '${cmd}'" >&2
    exit 1
    ;;
esac
