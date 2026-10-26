#!/usr/bin/env python3
"""family-lint — 驗 per-family versions.conf schema（build 值表的燃料；config/versions.conf 不在本檔範圍）。

用法：family-lint.py <family-versions.conf> [...]   逐檔驗證；任一失敗 exit 1。

兩種合法形態（互斥）：
  非-matrix：SERVICE_VERSION=vX.Y.Z（必）+ CHAIN（必，空白分隔）+ BASE? + UPSTREAM? + 任意第三方版本鍵
  matrix（如 taroko）：無 SERVICE_VERSION/CHAIN；UPSTREAM? + NODES（必）+ 至少一個 SERVERS_* 鍵

conf 會被 img.sh 以 source 讀入，**等同可執行程式碼**——文法檢查的位階等同機密掃描，不是風格檢查。
"""
import glob
import os
import re
import sys

REF_RE = re.compile(r"^v\d+\.\d+\.\d+$")
KEY_RE = re.compile(r"^([A-Z][A-Z0-9_]*)=(.*)$")
# 未加引號的值走白名單：任何 shell metachar（含空白）都會改變 source 的解析結果
UNQUOTED_OK_RE = re.compile(r"^[A-Za-z0-9._/:+=@,%-]*$")
# 引號內只需擋會展開的兩種：$ 開頭的命令替換／變數展開、反引號。& | ; 等在雙引號內是純字面
EXPAND_RE = re.compile(r"[$`]")
# FROM 拓撲引用:${REGISTRY_PREFIX}/<單段名>:<tag>。兩段路徑(library/…、minio/mc)因單段名後非 ':' 不匹配,天然跳過。
FROM_REF_RE = re.compile(r"^FROM\s+\$\{REGISTRY_PREFIX\}/([A-Za-z0-9_-]+):(\S+)")
FROM_LINE_RE = re.compile(r"^FROM\s")
# 自我檢查用的寬鬆候選式:單段名 + tag 內含 -${...}(即 <service>-<版本> 版式)。
# 兩段路徑(library/alpine、minio/mc)與 FROM scratch 本來就不匹配 FROM_REF_RE,不能拿它們當「規則脫節」的證據。
FROM_CANDIDATE_RE = re.compile(r"^FROM\s+\$\{REGISTRY_PREFIX\}/[^/\s]+:[^\s]*-\$\{")
# 光桿 ARG(無預設值)＝契約值;帶預設值的 ARG 是 Dockerfile 自有,不在此列
BARE_ARG_RE = re.compile(r"^ARG\s+([A-Z][A-Z0-9_]*)\s*$")
ENV_KEY_RE = re.compile(r"^ENV\s+([A-Za-z_][A-Za-z0-9_]*)=")
VAR_USE_RE = re.compile(r"\$\{([A-Z][A-Z0-9_]*)\}")
# 契約 ARG 名 ← conf 鍵名。與 infra/bin/img.sh 的 ARG_ALIAS 同一份語意,改一邊要改兩邊。
ARG_ALIAS = {
    "PROVISION_REF_IN": "PROVISION_REF",
    "JAVA_VERSION": "JAVA_DIR", "ZOOKEEPER_VERSION": "ZOOKEEPER_DIR",
    "KAFKA_VERSION": "KAFKA_DIR", "HADOOP_VERSION": "HADOOP_DIR",
    "HBASE_VERSION": "HBASE_DIR", "HIVE_VERSION": "HIVE_DIR",
    "SPARK_VERSION": "SPARK_DIR",
}
GLOBAL_KEYS = {"REGISTRY_PREFIX", "UPSTREAM_DOCKER", "PROVISION_REF"}
# matrix 衍生鍵:值來自 NODES／SERVERS_CRI_DOCKER 的單格迭代,由 img.sh 當 CLI 覆寫傳入,conf 內無此字面鍵
MATRIX_DERIVED = {"KUBERNETES_VERSION": "NODES", "KEY_VERSION": "SERVERS_CRI_DOCKER"}


def fail(path: str, msg: str) -> None:
    print(f"Error: {path}: {msg}", file=sys.stderr)
    sys.exit(1)


def parse_conf(path: str) -> dict:
    """解析 per-family versions.conf。文法違規即 fail——本檔會被 source，寫錯不是取不到值，是執行別的東西。"""
    data: dict = {}
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.read().split("\n")
    except FileNotFoundError:
        fail(path, "不存在")
    for ln, raw in enumerate(lines, 1):
        # 這道 rstrip 在現況是多餘的——open() 預設 newline=None（universal
        # newlines），\r\n 與單獨的 \r 在讀取時就已轉成 \n，字串裡不可能殘留 \r。
        # 留著是為了 newline='' 那種改法：真要逐位元讀時它就變成必要的。
        # 對照組：bash 側的讀取（pre-push）沒有這層保護，
        # 那邊的 ${line%$'\r'} 是真的在做事。
        line = raw.rstrip("\r")
        if not line or line.startswith("#"):
            continue
        m = KEY_RE.match(line)
        if not m:
            fail(path, f"第 {ln} 行不是 KEY=value（註解須獨立成行並以 # 開頭；鍵名須符合 ^[A-Z][A-Z0-9_]*$）")
        k, v = m.group(1), m.group(2)
        if k in data:
            fail(path, f"第 {ln} 行重複鍵：{k}")
        quoted = len(v) >= 2 and v[0] == '"' and v[-1] == '"'
        if v.startswith('"') and not quoted:
            fail(path, f"第 {ln} 行的雙引號未閉合：{k}（會把後續行一起吃進值裡）")
        inner = v[1:-1] if quoted else v
        if '"' in inner:
            fail(path, f"第 {ln} 行的值內含未跳脫的雙引號：{k}")
        if EXPAND_RE.search(inner):
            fail(path, f"第 {ln} 行的值含命令替換或變數展開（$ 或反引號）：{k}（conf 會被 source，值會被求值）")
        if not quoted and not UNQUOTED_OK_RE.match(inner):
            if " " in inner or "\t" in inner:
                fail(path, f"第 {ln} 行的值含空白但未加雙引號：{k}"
                           f"（bash 會解析成 assignment prefix 加指令並執行它，變數最終是 unset）")
            fail(path, f"第 {ln} 行的值含 shell metachar 但未加雙引號：{k}")
        data[k] = inner
    if not data:
        fail(path, "無有效宣告（空檔或全註解不算）")
    return data


def _value_table_keys(path: str, data: dict, is_matrix: bool) -> set:
    """值表鍵集合＝conf 字面鍵 + 全域三鍵 + upstream 衍生鍵 + matrix 衍生鍵。與 img.sh 的 build_args() 同義。"""
    keys = set(data) | GLOBAL_KEYS
    infra_dir = os.path.dirname(os.path.dirname(path))
    for up in data.get("UPSTREAM", "").split():
        pre = up.upper().replace("-", "_")
        up_conf = os.path.join(infra_dir, up, "versions.conf")
        if os.path.exists(up_conf):
            up_data = parse_conf(up_conf)
            if "SERVICE_VERSION" in up_data:
                keys.add(f"{pre}_SERVICE_VERSION")
            if "BASE" in up_data:
                keys.add(f"{pre}_BASE")
    if is_matrix:
        for derived, src in MATRIX_DERIVED.items():
            if src in data:
                keys.add(derived)
    return keys


def _logical_lines(path: str):
    """把反斜線續行併回邏輯行。alpine 的契約鍵用點幾乎全在 RUN 續行上,按實體行判斷會整批漏掉。"""
    out, buf, first = [], "", 0
    with open(path, encoding="utf-8") as f:
        for lineno, raw in enumerate(f, 1):
            line = raw.rstrip("\n")
            if not buf:
                first = lineno
            if line.rstrip().endswith("\\"):
                buf += line.rstrip()[:-1]
                continue
            out.append((first, buf + line))
            buf = ""
    if buf:
        out.append((first, buf))
    return out


def check_tpl_rules(path: str, data: dict, is_matrix: bool) -> None:
    """驗四條:(1) FROM 拓撲 (2) 光桿 ARG ⊆ 值表 (3) ARG 作用域 (4) 契約鍵不得為 ENV 鍵名。"""
    fam_dir = os.path.dirname(path)
    family = os.path.basename(fam_dir)
    flat = [] if is_matrix else data.get("CHAIN", "").split()
    upstream = data.get("UPSTREAM", "").split()
    vt_keys = _value_table_keys(path, data, is_matrix)
    from_matches = from_candidates = 0
    dockerfiles = sorted(glob.glob(os.path.join(fam_dir, "*.Dockerfile")))
    for df in dockerfiles:
        svc = os.path.basename(df)[: -len(".Dockerfile")]
        stage_idx = -1
        declared = [set()]          # index 0 為 global scope;每遇一個 FROM 開一個新 stage 集合
        env_keys, bare_args = set(), set()
        for lineno, line in _logical_lines(df):
            stripped = line.strip()
            if FROM_LINE_RE.match(stripped):
                stage_idx += 1
                declared.append(set())
                if FROM_CANDIDATE_RE.match(stripped):
                    from_candidates += 1
                m = FROM_REF_RE.match(stripped)
                if m:
                    from_matches += 1
                    ref_fam, tag = m.group(1), m.group(2)
                    if "-${" in tag:
                        ref_svc = tag.split("-${", 1)[0]
                        where = f"{df}:{lineno}"
                        if ref_fam == family:
                            if svc in flat:
                                if ref_svc not in flat:
                                    fail(path, f"{where}: FROM 引用 {family}:{ref_svc},但 {ref_svc} 不在 CHAIN")
                                if flat.index(ref_svc) >= flat.index(svc):
                                    fail(path, f"{where}: FROM 引用 {family}:{ref_svc},但其 CHAIN 順序不在 {svc} 之前(build 會 pull 不到)")
                        elif ref_fam not in upstream:
                            fail(path, f"{where}: FROM 跨家族引用 {ref_fam},但 UPSTREAM 未宣告(現況:{upstream or '無'})")
                continue
            m = BARE_ARG_RE.match(stripped)
            if m:
                name = m.group(1)
                bare_args.add(name)
                declared[stage_idx + 1].add(name)
                continue
            m = ENV_KEY_RE.match(stripped)
            if m:
                env_keys.add(m.group(1))
                # ENV 落進映像,同 stage 後續的 RUN 讀得到,不是「未宣告的 ARG 用點」。
                # 註:stage 之間不繼承同檔的 ENV(下一個 FROM 換 base),故仍按 stage 隔離。
                if stage_idx >= 0:
                    declared[stage_idx + 1].add(m.group(1))
            # 規則②:內文的 ${契約鍵} 必須在本 stage 宣告過(global scope 不流進 stage)
            if stage_idx >= 0:
                for used in VAR_USE_RE.findall(stripped):
                    src = ARG_ALIAS.get(used, used)
                    if src not in vt_keys and used not in vt_keys:
                        continue        # 規則④:非契約鍵(${PATH} 等)不反向誤報
                    if used not in declared[stage_idx + 1]:
                        fail(path, f"{df}:{lineno}: stage {stage_idx} 內文用了 ${{{used}}} 但該 stage 未宣告 ARG {used}"
                                   f"(ARG 不跨 stage,會靜默展開成空字串)")
        # 規則①:光桿 ARG ⊆ 值表
        for name in sorted(bare_args):
            src = ARG_ALIAS.get(name, name)
            if src not in vt_keys:
                fail(path, f"{df}: 光桿 ARG {name} 不在值表(conf 鍵、全域三鍵、upstream 衍生鍵、matrix 衍生鍵皆無 {src})")
        # 規則③:同名的光桿 ARG 與 ENV 不得並存。
        # 父映像帶的 ENV X 會蓋掉子映像同名的光桿 ARG X,--build-arg 被靜默忽略(已實測)。
        # 正解是改名:ARG X_IN + ENV X=${X_IN}——那種寫法沒有同名並存,不會命中本規則。
        for k in sorted(env_keys & bare_args):
            fail(path, f"{df}: 光桿 ARG {k} 與 ENV {k} 同名並存——父映像的 ENV 會蓋掉同名光桿 ARG,"
                       f"--build-arg 被靜默忽略。改成 ARG {k}_IN + ENV {k}=${{{k}_IN}}")
    # 正則寫死字面時會靜默關閉整條 FROM 拓撲規則(改 @{} → ${} 那次就差點發生),故自我檢查:
    # 有候選卻零匹配＝FROM_REF_RE 與樣板寫法脫節。只有兩段路徑或 FROM scratch 的 family
    # (如 open-webui)候選本來就是 0,不該被誤殺。
    if from_candidates > 0 and from_matches == 0:
        fail(path, f"FROM 拓撲規則零匹配,但有 {from_candidates} 條符合候選形態的 FROM"
                   "——FROM_REF_RE 與樣板寫法脫節")


def check_one(path: str) -> None:
    data = parse_conf(path)

    is_matrix = "NODES" in data or any(k.startswith("SERVERS_") for k in data)
    if is_matrix:
        if "SERVICE_VERSION" in data or "CHAIN" in data:
            fail(path, "matrix family 不得有 SERVICE_VERSION／CHAIN（tag 由 NODES／SERVERS_* 的單格迭代決定）")
        if not data.get("NODES", "").split():
            fail(path, "matrix 須有非空 NODES（空白分隔的版本清單）")
        if not any(k.startswith("SERVERS_") for k in data):
            fail(path, "matrix 須有至少一個 SERVERS_* 鍵")
    else:
        sv = data.get("SERVICE_VERSION", "")
        if not REF_RE.match(sv):
            fail(path, f"SERVICE_VERSION 須符合 vX.Y.Z，實際：{sv!r}")
        if not data.get("CHAIN", "").split():
            fail(path, "CHAIN 須為非空的空白分隔 service 清單（順序即 build 依賴序）")

    # 過渡期：infra/<family>/.imgctl 空標記＝該 family 已遷移到 imgctl，
    # Dockerfile 改用新寫法，舊規則（FROM 拓撲、①到④）不適用。conf 文法上面已驗過。
    fam_dir = os.path.dirname(path)
    if os.path.exists(os.path.join(fam_dir, ".imgctl")):
        family = os.path.basename(fam_dir)
        print(f"Info: {family} 已遷移到 imgctl，略過 Dockerfile 規則")
        return
    check_tpl_rules(path, data, is_matrix)
    print(f"Success: {path}（{'matrix' if is_matrix else 'non-matrix'} family schema+FROM 拓撲+ARG 契約合法）")


def main() -> None:
    if len(sys.argv) < 2:
        fail("(args)", "用法：family-lint.py <family-versions.conf> [...]")
    for p in sys.argv[1:]:
        check_one(p)


if __name__ == "__main__":
    main()
