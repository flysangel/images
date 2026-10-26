#!/bin/bash
# test_cronjob.sh — sync 同步 CronJob 的部署前斷言，驗 kubectl kustomize sync 的產物
# 註記：逐項容錯，捨棄 -e；每條斷言各自記 [OK]／[FAIL]，最後一次結算
# 用法：bash tests/test_cronjob.sh
# 驗規則 ConfigMap 的鍵與 sync/repository/*.yaml 一致、三項 Job 政策、不再 git clone、
# image 已解析、Secret 與 ConfigMap 的名稱與 CronJob 的引用一致。後兩件 kustomize 不會報錯，
# 名稱對不上時照樣 rc=0，要到叢集端 Pod 起不來才看得到。
set -uo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sync_dir="${repo_root}/sync"
golden="${repo_root}/tests/fixtures/cronjob/kustomize-out.golden.yaml"
pass=0
fail=0
ok()  { echo "[OK] ${1}"; pass=$((pass+1)); }
bad() { echo "[FAIL] ${1}" >&2; fail=$((fail+1)); }

# 印出指定 ConfigMap 的 data 鍵，排序後一行一個。$1 = kustomize 產物，$2 = ConfigMap 名。
# 靠 kustomize 的固定排版：文件以 --- 分隔、頂層鍵頂格、data 的鍵縮兩格、鍵值內容縮四格以上。
cm_keys() {
  printf '%s\n' "$1" | awk -v want="$2" '
    function flush() {
      if (is_cm && hit) for (i = 1; i <= n; i++) print keys[i]
      is_cm = 0; hit = 0; n = 0; in_data = 0
    }
    /^---$/ { flush(); next }
    /^kind: ConfigMap$/ { is_cm = 1 }
    $0 == "  name: " want { hit = 1 }
    /^data:$/ { in_data = 1; next }
    /^[^ ]/ { in_data = 0 }
    in_data && /^  [^ ]/ { k = $1; sub(/:$/, "", k); keys[++n] = k }
    END { flush() }
  ' | sort
}

# 印出缺少的 Job 政策，一行一個；全部都在時不印。縮排即欄位路徑：
# spec.concurrencyPolicy、spec.jobTemplate.spec.backoffLimit、spec.jobTemplate.spec.template.spec.restartPolicy。
missing_policies() {
  local line
  for line in '  concurrencyPolicy: Forbid' '      backoffLimit: 0' '          restartPolicy: Never'; do
    if ! printf '%s\n' "$1" | grep -qxF -- "${line}"; then
      printf '%s\n' "${line#"${line%%[![:space:]]*}"}"
    fi
  done
}

# 印出 CronJob volumes 引用的 ConfigMap 名，排序後一行一個
volume_cms() {
  printf '%s\n' "$1" | grep -A1 -xF -- '          - configMap:' | sed -n 's|^[[:space:]]*name:[[:space:]]*||p' | sort
}

# ===== 第一段：擷取器的自我檢查（罐頭產物，不需 kubectl） =====
# 擷取器與真產物的排版脫節時，第二段會靜默變成什麼都沒驗；這段用形狀相同的罐頭產物先驗擷取器本身。
if [[ -f "${golden}" ]]; then
  golden_out="$(cat "${golden}")"

  got="$(cm_keys "${golden_out}" skopeo-rules | paste -sd ' ' -)"
  if [[ "${got}" == "alpha.yaml beta.yaml" ]]; then
    ok "自我檢查：罐頭產物的 skopeo-rules 鍵取得 alpha.yaml beta.yaml，不混進 skopeo-script 的鍵"
  else
    bad "自我檢查：罐頭產物的 skopeo-rules 鍵取得「${got}」；擷取器與產物形狀脫節"
  fi

  # 漏列：刪掉 beta.yaml 的鍵行，它的內容行留著也不可被當成鍵
  got="$(cm_keys "${golden_out//  beta.yaml: |/}" skopeo-rules | paste -sd ' ' -)"
  if [[ "${got}" == "alpha.yaml" ]]; then
    ok "自我檢查：少一把鍵時只取得 alpha.yaml"
  else
    bad "自我檢查：少一把鍵時取得「${got}」"
  fi

  got="$(cm_keys "${golden_out}" skopeo-script | paste -sd ' ' -)"
  if [[ "${got}" == "start.sh" ]]; then
    ok "自我檢查：罐頭產物的 skopeo-script 鍵取得 start.sh"
  else
    bad "自我檢查：罐頭產物的 skopeo-script 鍵取得「${got}」"
  fi

  got="$(missing_policies "${golden_out}" | paste -sd ' ' -)"
  if [[ -z "${got}" ]]; then
    ok "自我檢查：罐頭產物三項 Job 政策都認得到"
  else
    bad "自我檢查：罐頭產物被判缺政策「${got}」；擷取器與產物形狀脫節"
  fi

  got="$(missing_policies "${golden_out//backoffLimit: 0/backoffLimit: 6}" | paste -sd ' ' -)"
  if [[ "${got}" == "backoffLimit: 0" ]]; then
    ok "自我檢查：backoffLimit 改成 6 判為缺政策"
  else
    bad "自我檢查：backoffLimit 改成 6 時取得「${got}」"
  fi

  got="$(volume_cms "${golden_out}" | paste -sd ' ' -)"
  if [[ "${got}" == "skopeo-rules skopeo-script" ]]; then
    ok "自我檢查：罐頭產物的 volumes 取得兩個 ConfigMap 名"
  else
    bad "自我檢查：罐頭產物的 volumes 取得「${got}」；擷取器與產物形狀脫節"
  fi
else
  bad "缺罐頭產物 ${golden}；擷取器無法自我檢查"
fi

# ===== 第二段：真產物斷言（需 kubectl） =====
if ! command -v kubectl >/dev/null; then
  echo "[SKIP] 無 kubectl，略過 kustomize 產物斷言（上方自我檢查已跑）"
  echo "${pass} passed, ${fail} failed"
  [[ "${fail}" -eq 0 ]]
  exit
fi

# 真值檔 secret.env 不進版控，乾淨 clone 與 worktree 上不存在，secretGenerator 缺來源會讓
# kubectl kustomize rc=1。複製整個 sync/ 到暫存樹再用 .example 補位，repo 內零寫入。
if [[ ! -f "${sync_dir}/secret/secret.env" ]]; then
  tmp_root="$(mktemp -d)"
  trap 'rm -rf "${tmp_root}"' EXIT
  cp -r "${sync_dir}" "${tmp_root}/"
  cp "${tmp_root}/sync/secret/secret.env.example" "${tmp_root}/sync/secret/secret.env"
  sync_dir="${tmp_root}/sync"
  echo "Info: 無 sync/secret/secret.env，改用 .example 的佔位值在暫存樹驗證"
fi

out="$(kubectl kustomize "${sync_dir}" 2>&1)" || {
  bad "kubectl kustomize 失敗: ${out}"
  echo "${pass} passed, ${fail} failed"
  exit 1
}

# 規則 ConfigMap 的鍵必須等於 repository/*.yaml：kustomization 的清單漏列，該檔在叢集端不會同步；
# 多列一個不存在的檔，kustomize 會 rc=1，上面就擋下了；多列 repository 以外的檔，這裡擋
want="$(for f in "${repo_root}"/sync/repository/*.yaml; do basename "${f}"; done | sort)"
got="$(cm_keys "${out}" skopeo-rules)"
if [[ -n "${got}" && "${got}" == "${want}" ]]; then
  ok "skopeo-rules 的鍵與 sync/repository/*.yaml 一致（$(printf '%s\n' "${got}" | wc -l) 檔）"
else
  bad "skopeo-rules 的鍵與 sync/repository/*.yaml 不一致，改 sync/kustomization.yaml 的清單："
  diff <(printf '%s\n' "${want}") <(printf '%s\n' "${got}") | sed -n 's/^< /       漏列 /p; s/^> /       多列 /p' >&2
fi

got="$(cm_keys "${out}" skopeo-script)"
if [[ "${got}" == "start.sh" ]]; then
  ok "skopeo-script 只含 start.sh"
else
  bad "skopeo-script 的鍵是「${got}」，應只有 start.sh"
fi

got="$(missing_policies "${out}")"
if [[ -z "${got}" ]]; then
  ok "三項 Job 政策都在（concurrencyPolicy: Forbid、backoffLimit: 0、restartPolicy: Never）"
else
  bad "缺 Job 政策（一輪要跑 8 到 12 小時，失敗不可整批重跑）："
  printf '%s\n' "${got}" | sed 's/^/       /' >&2
fi

if printf '%s\n' "${out}" | grep -q 'git clone'; then
  bad "CronJob 仍含 git clone；規則與腳本應由 ConfigMap 掛載"
else
  ok "CronJob 不含 git clone"
fi

if printf '%s\n' "${out}" | grep -qxF -- '            - /opt/sync/bin/start.sh'; then
  ok "CronJob 執行 ConfigMap 掛進來的 /opt/sync/bin/start.sh"
else
  bad "CronJob 的 command 沒有 /opt/sync/bin/start.sh"
fi

got="$(volume_cms "${out}" | paste -sd ' ' -)"
if [[ "${got}" == "skopeo-rules skopeo-script" ]]; then
  ok "volumes 引用的 ConfigMap 名與 generator 一致"
else
  bad "volumes 引用的 ConfigMap 名是「${got}」，應為 skopeo-rules skopeo-script（kustomize 不會報，Pod 會卡在 ContainerCreating）"
fi

if printf '%s\n' "${out}" | grep -q 'image: quay.io/flysangel/alpine:podman-'; then
  ok "kustomize images: 已解析為完整參照"
else
  bad "image 未解析（短名殘留或 kustomization 的 name 打錯）"
fi

# generator 產出的 Secret 名必須等於 CronJob 的 envFrom.secretRef 名。
# kustomize 的 legacy sort 把 Secret 排在 CronJob 前，故各取第一筆。
gen_name="$(printf '%s\n' "${out}" | awk '/^kind: Secret$/{f=1} f && /^  name: /{print $2; exit}')"
ref_name="$(printf '%s\n' "${out}" | grep -A2 'secretRef:' | sed -n 's|^[[:space:]]*name:[[:space:]]*||p' | head -1)"
if [[ -n "${gen_name}" && "${gen_name}" == "${ref_name}" ]]; then
  ok "Secret 名與 envFrom.secretRef 一致（${gen_name}）"
else
  bad "Secret 名不一致：generator=${gen_name} secretRef=${ref_name}（kustomize 不會報，叢集端 CronJob 會起不來）"
fi

echo "${pass} passed, ${fail} failed"
[[ "${fail}" -eq 0 ]]
