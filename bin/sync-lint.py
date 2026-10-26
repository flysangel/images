#!/usr/bin/env python3
"""sync-lint — 驗 sync/repository/*.yaml 的同步規則 schema。

用法：sync-lint.py <repository yaml> [...]   逐檔驗證；任一失敗 exit 1。

為什麼需要這支：`sync/bin/start.sh` 不設 `-e`，因為單顆映像失敗不該中止整批。同步失敗時，
流程是 retry 三次 → `Info: [skip]` → 迴圈繼續，全部跑完後有失敗就 `exit 1`。Job 因此顯示
失敗，但只看得到「有映像沒同步」，看不出是哪個規則檔壞了。本檔在 commit 前先擋 schema
錯誤。`family-lint.py` 只管 `versions.conf`。

驗五條：
  ① YAML 可解析且頂層是 mapping
  ② 頂層鍵（registry 主機）須在 start.sh 會登入的主機集合內——**白名單自 start.sh 推導**，
     不硬編。指向沒有憑證的私有 registry 時，匿名拉取會回 401，而且要到同步時才會出現。
  ③ 第二層恰為 `images-by-tag-regex`，且值是非空 mapping
  ④ image 名須為 `<namespace>/<name>` 形狀
  ⑤ 每條 tag regex 可編譯（skopeo 側編譯失敗＝該檔整批不同步，到同步時才失敗）
另驗檔名：`start.sh` 以 `basename -s .yaml` 當同步目標的 repo 名（`${DEST}${image}`），
故檔名須是合法的 registry path 段。
"""
import os
import re
import sys

import yaml

IMAGE_RE = re.compile(r"^[a-z0-9]+(?:[._-][a-z0-9]+)*/[a-z0-9]+(?:[._-][a-z0-9]+)*$")
FILENAME_RE = re.compile(r"^[a-z0-9]+(?:[._-][a-z0-9]+)*$")
# start.sh 的非憑證常數區:`: "${DOCKER:=docker.io}"` 這種 shell 預設值賦值
HOST_DEFAULT_RE = re.compile(r'\$\{[A-Z_]+:=([a-z0-9.-]+\.[a-z]{2,})\}')


def fail(path: str, msg: str) -> None:
    print(f"Error: {path}: {msg}", file=sys.stderr)
    sys.exit(1)


def allowed_hosts(start_sh: str) -> set:
    """自 start.sh 的 shell 預設值賦值推導主機白名單(而非在本檔硬編第二份清單)。"""
    try:
        with open(start_sh, encoding="utf-8") as f:
            hosts = set(HOST_DEFAULT_RE.findall(f.read()))
    except FileNotFoundError:
        fail(start_sh, "不存在——主機白名單自本檔推導,缺檔即無法驗證(不靜默放行)")
    if not hosts:
        fail(start_sh, "取不到任何 registry 主機預設值——HOST_DEFAULT_RE 與 start.sh 寫法脫節")
    return hosts


def check_one(path: str, hosts: set) -> None:
    name = os.path.basename(path)
    if not name.endswith(".yaml"):
        fail(path, "副檔名須為 .yaml(start.sh 的 find 只收 *.yaml)")
    stem = name[: -len(".yaml")]
    if not FILENAME_RE.match(stem):
        fail(path, f"檔名 {stem!r} 不是合法的 registry path 段"
                   "(start.sh 以 basename -s .yaml 當同步目標的 repo 名)")
    try:
        with open(path, encoding="utf-8") as f:
            data = yaml.safe_load(f)
    except FileNotFoundError:
        fail(path, "不存在")
    except yaml.YAMLError as e:
        fail(path, f"YAML 解析失敗:{str(e).splitlines()[0]}")
    if not isinstance(data, dict) or not data:
        fail(path, "頂層須為非空 mapping(registry 主機 → 規則)")
    n_rules = 0
    for host, body in data.items():
        if host not in hosts:
            fail(path, f"registry 主機 {host!r} 不在 start.sh 會登入的集合內"
                       f"（現況:{', '.join(sorted(hosts))}）——匿名拉取私有 registry 會 401,而 401 也是靜默 skip")
        if not isinstance(body, dict) or not body:
            fail(path, f"{host} 的值須為非空 mapping")
        extra = set(body) - {"images-by-tag-regex"}
        if extra:
            fail(path, f"{host} 出現非預期鍵:{', '.join(sorted(extra))}"
                       "(本 repo 一律用 images-by-tag-regex)")
        table = body.get("images-by-tag-regex")
        if not isinstance(table, dict) or not table:
            fail(path, f"{host}.images-by-tag-regex 須為非空 mapping")
        for image, pattern in table.items():
            if not isinstance(image, str) or not IMAGE_RE.match(image):
                fail(path, f"{host} 的 image 名 {image!r} 不是 <namespace>/<name> 形狀")
            if not isinstance(pattern, str) or not pattern:
                fail(path, f"{host}/{image} 的 tag regex 須為非空字串,實際:{pattern!r}")
            try:
                re.compile(pattern)
            except re.error as e:
                fail(path, f"{host}/{image} 的 tag regex 無法編譯:{pattern!r}（{e}）")
            n_rules += 1
    print(f"Success: {path}（{len(data)} 個主機／{n_rules} 條規則）")


def main() -> None:
    if len(sys.argv) < 2:
        fail("(args)", "用法：sync-lint.py <repository yaml> [...]")
    # 白名單來源以本檔位置推 repo 根,不靠工作目錄;SYNC_START_SH 供測試與 pre-push 覆寫
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    start_sh = os.environ.get("SYNC_START_SH", os.path.join(repo_root, "sync", "bin", "start.sh"))
    hosts = allowed_hosts(start_sh)
    for p in sys.argv[1:]:
        check_one(p, hosts)


if __name__ == "__main__":
    main()
