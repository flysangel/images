# images 架構

images 的結構與設計取捨。操作指令見 [../README.md](../README.md)，動手前的地雷見 [../AGENTS.md](../AGENTS.md)。

## 1. 定位與邊界

```
provision ──釘 PROVISION_REF──> images ──發佈 docs/images-manifest.yaml──> 釘 IMAGES_REF 的下游
                                   │
                         推映像 ───┴──> quay.io/flysangel

app-services 直接拉映像，不讀 manifest，也不釘 IMAGES_REF
```

- **上游只有一條**：`provision`（建置期的二跳腳本，以 `raw/<tag>/` 引用）。它不反向依賴 images。
- **對下游單向發佈**：images 發佈版本清單，釘 `IMAGES_REF` 的下游從 raw 路徑讀，不手寫 image tag。images 改建置機制，下游不會馬上受影響；下游要主動升 `IMAGES_REF` 才會看到變化。這層雙重釘選讓下游自己決定什麼時候升級。
- **誰在讀 manifest**：在下游 repo 搜 `IMAGES_BASE_URL` 找得到 adapter。取值模式一致：讀自己 `versions.conf` 的 `IMAGES_REF`，curl raw manifest，用 yq 取 `.images.<family>.<service>`；matrix family（taroko）取陣列，例如 `.images.taroko.nodes[]`。yq 只出現在下游，本 repo 內部不用 yq。
- **push 護欄**是本 repo 自帶的 `.githooks/pre-push`，由帳號層派工 hook 呼叫；本 repo 自有的檢查見〈治理層〉。

## 2. 目錄結構

| 路徑 | 內容 |
|---|---|
| `CLAUDE.md` | 只寫 `@AGENTS.md`，讓 Claude Code 讀本 repo 的 `AGENTS.md` |
| `AGENTS.md` | 本 repo 的地雷、限制與驗證方式 |
| `README.md` | 安裝與用法 |
| `LICENSE` | Apache License 2.0 全文，規則見 `~/.claude/rules/directories.md`〈根層〉 |
| `docs/ARCHITECTURE.md` | 本檔 |
| `docs/PROGRESS.md` | 目前狀態與還沒做的工程、維運待辦 |
| `docs/images-manifest.yaml` | 對下游發佈的版本清單，由 `img.sh manifest` 產生，不手寫 |
| `docs/superpowers/`、`docs/tickets/` | spec、plan 與工作票，本機暫存，不進版控 |
| `Taskfile.yaml` | 操作入口，include `sync/taskfile.yaml`，task 清單見 `task --list-all`。還沒包進 task 的操作見 [../README.md](../README.md)〈建映像〉與〈上游同步〉 |
| `config/` | repo 層級的設定：`versions.conf` 釘本 repo 消費的上游版本 `PROVISION_REF`，文法見檔頭。目錄的規則見 `~/.claude/rules/directories.md` |
| `bin/` | 治理腳本：family 與同步規則的 lint、執行環境檢查、四大文件與 Taskfile 檢查，清單見 `ls bin/`。`check-docs.py` 與 `check-taskfile.py` 是個人環境來源 repo 的副本 |
| `infra/` | 自建映像 family。有 `versions.conf` 的子目錄才是 family，清單見 `ls infra/*/versions.conf`。每個 family 放 `*.Dockerfile` 正本、`versions.conf`、煙霧測試 testfile（matrix family 的 taroko 沒有）、`README.md` 與映像內容物 |
| `infra/bin/img.sh` | 建置協調者，值表組裝也在裡面。`infra/bin/` 不是 family |
| `infra/fbs/docker_config.json` | filebrowser 的設定檔，COPY 成映像內的 `/root/.filebrowser.json` |
| `infra/gmm/ext/guac-manifest.json`、`infra/gmm/ext/translations/en.json` | Guacamole extension 的 manifest 與英文翻譯，由 Guacamole 讀 |
| `sync/` | 上游同步：規則（`repository/`）、執行腳本（`bin/start.sh`）、叢集部署（kustomize 與 `deploy/`），`mirror`、`apply:namespace`、`apply:cronjob` 三個 task 定義在 `sync/taskfile.yaml` |
| `sync/secret/` | registry 憑證的 Secret 宣告。真值檔 `secret.env` 不進版控，範本 `secret.env.example` 進版控 |
| `tests/` | 工具鏈單元測試：手寫 bash harness 與 `fixtures/`（stub、假 family、壞規則檔、罐頭 kustomize 產物、`config/versions.conf` 的替身），清單見 `ls tests/ tests/fixtures/` |
| `.githooks/` | push 護欄 `pre-push` 與它的規則檔，以個人環境來源 repo 的 `pre-push` 為底，另加本 repo 專屬的 `scan_repo`。檔案見 `ls .githooks/` |
| `.claude/worktrees/` | 本 repo 的 worktree 落點 |

## 3. 依賴與資料流

### 版本契約三層

```
config/versions.conf          PROVISION_REF                         ← 沒有程式驗，靠人維持
infra/<family>/versions.conf  BASE、SERVICE_VERSION、CHAIN、        ← family-lint.py 驗
                              UPSTREAM、第三方版本鍵
docs/images-manifest.yaml     由上面衍生，不手寫                    ← img.sh manifest 產生
```

**`config/versions.conf`** 的值必須是 `vX.Y.Z`。留空時，宣告 `PROVISION_REF_IN` 的 Dockerfile 在組值表時失敗。文法是嚴格子集：鍵頂格、無引號、無行尾註解、等號旁無空白，所以讀取都退化成 `${line#*=}`。

**各 family 的 `versions.conf`** 有兩種互斥形態：

| 形態 | 必要鍵 | 選配 |
|---|---|---|
| 非 matrix | `SERVICE_VERSION`（`vX.Y.Z`）、`CHAIN`（空白分隔的一維清單） | `BASE`、`UPSTREAM`、第三方版本鍵 |
| matrix（只有 `taroko`） | `NODES`、至少一個 `SERVERS_*` | `UPSTREAM`、第三方版本鍵 |

matrix 形態不得出現 `SERVICE_VERSION` 與 `CHAIN`。`family-lint.py` 與 `img.sh` 的 `family_is_matrix()` 用同一個判準：有 `NODES` 或任一 `SERVERS_*` 鍵。

family conf 被 `source` 讀，等同可執行程式碼，所以文法和 `config/versions.conf` 相反：**含空白的值必須加雙引號**。第三方版本鍵直接寫成頂層大寫底線鍵，下載網址與 checksum 也放這裡做版本釘選，取代建置期查 `releases/latest` 的浮動行為。

### 值表組裝：從 versions.conf 到 --build-arg

```
   infra/<family>/versions.conf ─┐
   config/versions.conf          ├─> img.sh build_args() ─> --build-arg K=V …
   upstream family 的 conf       │     （組值表，再與該 Dockerfile
   內建全域值                    │       的光桿 ARG 集合取交集）
   CLI KEY=VAL（最高）          ─┘                │
                                                  ▼
                              pbuild -f infra/<family>/<service>.Dockerfile
```

`build_args()` 由低到高疊五層：

| # | 層 | 來源 |
|---|---|---|
| 1 | 內建全域 | `REGISTRY_PREFIX`、`UPSTREAM_DOCKER`（`img.sh` 內的字面值） |
| 2 | `config/versions.conf` | `PROVISION_REF` |
| 3 | upstream 衍生 | `UPSTREAM` 列出的 family，取其 `SERVICE_VERSION`、`BASE` 並加 family 名前綴，例如 `UBUNTU_SERVICE_VERSION` |
| 4 | 本 family conf | 全部的鍵 |
| 5 | CLI `KEY=VAL` | 優先最高；taroko 的單格選取就是靠這層 |

組完後與 Dockerfile 的光桿 ARG 集合取交集，缺鍵就立刻失敗，並指出要去看哪個 conf。光桿 ARG 的判準與 ARG 不跨 stage 的坑見 [../AGENTS.md](../AGENTS.md)〈光桿 `ARG` 就是契約值〉。

**組合型 ARG**：拆成兩個光桿 ARG 加一個帶預設值的組合 ARG，組合留在 Dockerfile。多半是為了讓 `# hadolint ignore=` 抑制得到目標指令：

```dockerfile
ARG REGISTRY_PREFIX
ARG ALPINE_SERVICE_VERSION
ARG DOWNLOADER_IMAGE=${REGISTRY_PREFIX}/alpine:base-${ALPINE_SERVICE_VERSION}
FROM ${DOWNLOADER_IMAGE} AS downloader
```

**`ARG_ALIAS`**：Dockerfile 側 ARG 名與 conf 鍵名不同的對應，寫在值表層，不散進 Dockerfile。一類是 `PROVISION_REF_IN ← PROVISION_REF`（避開父映像的 `ENV PROVISION_REF`）；另一類是 bigdata 的 `*_VERSION ← *_DIR`，值是解壓後的目錄名：`hconfig` 把 `/conf/<目錄名>/` 底下的檔逐一對應到 `/opt/<同名目錄>/`，所以 Dockerfile 的 `COPY … /conf/${X_VERSION}` 必須與 tar 解開的目錄同名，別名讓 Dockerfile 用版本鍵名寫得出這個路徑。查表順序是「先看有沒有同名的值，沒有才走別名」；反過來，CLI 對別名鍵的覆寫會被換回來源鍵的值。

### family 模型

`CHAIN` 是建置順序，也是 `family-lint.py` 驗 FROM 引用的依據：同一個 family 的 FROM 只能引用序位在自己之前的 service。它不等於 FROM 依賴圖；lint 只驗「引用者在被引用者之後」這個單向約束。

一個 family 共用一個 `SERVICE_VERSION`，tag 形如 `<registry>/<family>:<service>-<version>`。

| family | 定位 |
|---|---|
| `alpine` | Alpine 基底鏈 |
| `ubuntu` | Ubuntu 基底鏈 |
| `bigdata` | Hadoop 系譜的單機鏈與 HA 變體 |
| `fbs` | filebrowser |
| `open-webui` | Open WebUI 帳號管理 helper |
| `rdp` | 桌面環境 × 角色的矩陣 |
| `gmm` | Guacamole 三件組 |
| `landlord` | 多租戶 SSH 平台 |
| `taroko` | K8s node 與 server 映像，matrix 形態 |

完整清單見 `catalog.yaml` 與 `ls infra/*/versions.conf`（已遷移的 family 只在前者，沒有 `versions.conf`）。跨 family 的 FROM 用 `grep -n '^FROM' infra/*/*.Dockerfile` 查，建置順序寫在 `infra/bin/img.sh` 的 `FAMILIES_DEFAULT` 註解。`open-webui:dbadm` 的 FROM 是上游 alpine（`${LIBRARY_ALPINE_IMAGE}`）而不是 `alpine:base`。外部父映像大多經 `${REGISTRY_PREFIX}` 取自家同步的副本，例外寫在該 Dockerfile 的註解。base 層只有 root；`bigred` 由 sshd 層跑 provision 的 `bigred.txt` 建立，直接疊在 base 上的 service 只能用 root。

**taroko 是 matrix**：沒有 `SERVICE_VERSION` 與 `CHAIN`，由 `NODES`、`SERVERS_CRI_DOCKER`、`SERVERS_DOCKER` 三個一維鍵宣告格子，`img.sh` 逐格迭代並把單格值當 CLI 覆寫傳進 `build_args()`。`KUBERNETES_VERSION` 與 `KEY_VERSION` 是矩陣衍生鍵，conf 裡沒有字面鍵；`family-lint.py` 的值表也要認得它們。矩陣之間無依賴，所以 `ci` 每建完一格就刪，控制磁碟峰值。taroko 沒有 testfile。三種格子的 tag 文法不同：node 直接用 K8s 版本當 tag，server 兩格帶 `cri-docker-` 與 `docker-` 前綴；下游讀 manifest 的三個陣列時照這個文法選映像。

**映像內容物**：Dockerfile 之外、`COPY` 進映像在 runtime 執行的腳本與設定，例如 `infra/bigdata/bin/`、`infra/landlord/bin/`、`k8sadm-entry.sh`。它們的終端輸出是容器內服務日誌，不受營運腳本的 `Error:`、`Success:`、`Info:` 慣例約束，也不納入 shellcheck 零告警基準。同一份內容物在不同 family 各放一份，例如 `kube/config` 與 `k8sadm-entry.sh` 在 alpine 與 rdp 各有，刻意不跨 family 共用，查法 `diff infra/alpine/kube/config infra/rdp/kube/config`。

bigdata 的容器以 bigred 執行而 `/opt` 歸 root，內容物腳本動到系統路徑都走 sudo。每顆的 CMD 組成固定：`hconfig` 渲染設定、依角色跑 start 腳本、最後 `sudo /usr/sbin/sshd -D` 前景保活。資料目錄全部放在 `/home/<HDUSER>` 底下，`hconfig` 結尾把整個家目錄 chown 給當前使用者。

### img.sh：協調層

`infra/bin/img.sh` 是唯一的建置協調者。不帶參數執行會印出全部子命令；另有除錯用的 `__dump_build_args`。

| 子命令 | 組值表 | 建置 | 測試 | 事後 |
|---|---|---|---|---|
| `build` | ✓ | ✓ | — | 保留 |
| `test` | — | — | ✓ | 保留 |
| `dev` | ✓ | ✓ | ✓ | 保留（主開發迴圈） |
| `ci` | ✓ | ✓ | ✓ | 全過才刪；失敗保留供除錯。taroko 例外，每建完一格就刪 |

各函式的實作紀律（`pbuild` 的 sudo 與 `--format docker`、FD 3 迴圈、`require_family` 守衛、刻意的小重複）寫在 `img.sh` 各函式上方的註解。`FAMILIES`、`MANIFEST_OUT` 這類環境變數給測試 fixtures 與手動比對用，日常建置不設，清單用 `grep -n ':-' infra/bin/img.sh` 查。

**testfile 契約**：每個非 matrix 的 service 有一支 `infra/<family>/<service>.testfile`。呼叫方式是 `bash <testfile> "<family>:<service>-<version>"`，`REGISTRY_PREFIX` 由 `img.sh` 注入。一律 `set -euo pipefail`，沒有共用 helper，每支自足；輸出只有 `[test]`、`[FAIL]`、`[OK]`。起容器的寫法固定：`sudo podman run --rm --privileged --network bridge --name repotest -d`，再用 `podman inspect` 取容器 IP 從建置機直連，不映射 host 埠。疊在桌面層或 sshd 層上的 service，testfile 只驗本層加的工具，不重跑下層已驗過的協定路徑。

### sync：上游同步

```
sync/repository/*.yaml   上游同步規則，一個 vendor 一檔
        ↓ 檔名（去 .yaml）決定目的地 repo 名
sync/bin/start.sh        skopeo login → skopeo sync --src yaml --dest docker
                         每個規則檔最多重跑 MAX_ATTEMPTS 次，skopeo 再對每顆重試；
                         失敗的規則檔累計到最後列出，有失敗就 exit 1
```

規則檔是 skopeo `--src yaml` 的原生格式：

```yaml
<upstream-registry-host>:
  images-by-tag-regex:
    <namespace>/<repo>: <tag regex，skopeo 用 Go 的 RE2 語法>
```

`vllm.yaml` 與 `pgvector.yaml` 只收目前使用的次版號。vLLM 映像很大，收全部版本會搬進大量舊版；代價是升次版號要改兩處：本 repo 的規則與 app-services 的映像版號。規則檔有兩種收錄取向並存：多數收數字版加 `latest`（有的另收 alpine 或 lts 變體），少數不收 `latest`、只收目前使用的次版號，查法 `grep -L latest sync/repository/*.yaml`。只收 `latest` 的規則釘不了版，見 [PROGRESS.md](PROGRESS.md)。

`skopeo sync` 不帶 `--scoped`：目的地是規則檔名加來源映像路徑的最後一段，來源的 namespace 被丟掉，例如 `milvusdb/milvus` 落在 `<registry>/milvus/milvus`。同一個規則檔裡兩顆映像最後一段相同時會互相覆蓋，`sync-lint.py` 不驗這點。

**叢集端**：`sync/kustomization.yaml` 是入口，可直接 `kubectl kustomize sync`。

| 檔 | 內容 |
|---|---|
| `sync/kustomization.yaml` | namespace `svc`、`configMapGenerator`（`skopeo-script` 裝 `start.sh`、`skopeo-rules` 裝規則檔）、`images:` 把短名 `skopeo` 映到 alpine 的 podman 映像 |
| `sync/deploy/cronjob.yaml` | CronJob 本體，每日排程；直接執行 `/opt/sync/bin/start.sh`，憑證由 Secret 以 `envFrom` 注入 |
| `sync/secret/` | 憑證 Secret 的宣告（`secretGenerator`） |

同步容器借用自家 `alpine:podman` 映像，`start.sh` 需要它提供 bash、免密 sudo 與 skopeo；`infra/alpine/podman.testfile` 驗得到 skopeo，換映像前先確認。ConfigMap 掛載的檔是指向 `..data` 的 symlink，`start.sh` 因此用 `find -L -maxdepth 1 -type f`，`here` 也不能改用 `readlink -f` 算。Job 政策是 `concurrencyPolicy: Forbid`、`backoffLimit: 0`、`restartPolicy: Never`：一輪要跑很久，上一輪沒跑完不起新的，失敗也不整批重跑。

憑證只有一個載體：gitignored 的 `sync/secret/secret.env`，範本是 `secret.env.example`。本機由 task 的 `dotenv:` 讀，叢集由 `secretGenerator` 讀，同一份來源。格式是**值一律裸寫**：kustomize 的 dotenv 解析不剝引號。

`tests/test_cronjob.sh` 在套用前驗 kustomize 產物：規則清單與 `sync/repository/*.yaml` 一致、Job 政策、映像已解析成完整參照、Secret 與 ConfigMap 的名稱與 CronJob 的引用一致。擷取器先對罐頭產物 `tests/fixtures/cronjob/kustomize-out.golden.yaml` 自我檢查，排版脫節時才不會靜默變成什麼都沒驗。

### manifest：對下游的契約

`img.sh manifest` 從各 family 的 `versions.conf` 產生 `docs/images-manifest.yaml`。一般 family 是 service → tag 的對照，matrix family（taroko）是 `nodes`、`cri-docker`、`docker` 三個陣列，另加一行 `registry_prefix`。不含 `IMAGES_REF`：下游在自己的 `versions.conf` 記自己釘的版本。

下游讀取路徑：`https://gitlab.com/flysangel/images/-/raw/<IMAGES_REF>/docs/images-manifest.yaml`。各 adapter 有 `IMAGES_BASE_URL` 可指向 `file://` fixture。

### 治理層

| 工具 | 驗什麼 | 觸發 |
|---|---|---|
| `bin/family-lint.py` | family `versions.conf` 的文法與 schema、FROM 拓撲、ARG 契約 | `task lint:family`、`task lint`、push 護欄 |
| `bin/sync-lint.py` | 同步規則的 schema；主機白名單從 `start.sh` 推導 | `task lint`、push 護欄 |
| `bin/check-docs.py`、`bin/check-taskfile.py` | 四大文件的必要節與引用、Taskfile 的分類原則 | `task lint`、push 護欄 |
| `tests/test_*.sh` | 各工具本身 | `task test` |
| `shellcheck -S warning` | 營運腳本、測試與 stub 零告警 | `task lint` |

`family-lint.py` 的 `check_tpl_rules()` 對每個 Dockerfile 驗：

| 規則 | 為什麼要有 |
|---|---|
| FROM 拓撲：同 family 在 `CHAIN` 內、序位在前、跨 family 已宣告 `UPSTREAM` | 建置時拉不到上游映像 |
| ① 光桿 ARG ⊆ 值表鍵集合 | 打錯鍵名會拖到建置期才失敗，訊息離根因遠 |
| ② stage 內文用的契約鍵，該 stage 必須宣告過 | ARG 不跨 stage 會靜默展開成空字串 |
| ③ 同名的光桿 ARG 與 ENV 不得並存 | 父映像的 ENV 會蓋掉 `--build-arg` |
| ④ 非契約鍵（例如 `${PATH}`）不被②反向誤報 | 內文掃描只認值表裡的鍵 |

兩個實作細節防止規則靜默關閉：內文掃描先把反斜線續行併成邏輯行；FROM 拓撲有自我檢查，有候選 FROM 卻零匹配就報錯。

## 4. 設計取捨

- **值注入用 Docker 原生 ARG，不自建渲染引擎。** 光桿 `ARG X` 就是契約值，判準是 Docker 語法本身，lint 與 podman 看到的是同一件事。缺鍵在組 `--build-arg` 時就失敗，不會拖到建置期展開成空字串。只傳宣告過的 ARG，避開 podman 對「供了但未宣告」的警告。代價：Dockerfile 不能直接 `podman build`；`PROVISION_REF_IN` 的命名與其他契約鍵不一致；忘記在 stage 內重宣告 ARG 是靜默失敗面。缺鍵由 `img.sh` 組值表時擋下，這個分支沒有 `tests/test_img.sh` 的 case；stage 內漏宣告由 `lint:family` 的規則②擋下。
- **契約鍵不統一加前綴。** 所有契約 ARG 加前綴就不會撞 ENV，但要改每個 Dockerfile 的每個 ARG 名與 FROM 行，可讀性下降。只有撞名的 `PROVISION_REF` 用別名。同一個 Dockerfile 內的撞名由 `lint:family` 的規則③擋下；父映像的 `ENV` 蓋掉子映像同名的光桿 `ARG`，兩者在不同檔，無程式擋。
- **值解析收在 img.sh，不另立 adapter。** 值解析只有 `img.sh` 一個消費者，`build_args()` 的行為由 `tests/test_img.sh` 擋下，缺鍵分支還沒有 case；`__dump_build_args` 供人工檢視值表。
- **一個 family 一個版本號。** 粗粒度換來 FROM 鏈與 tag 邏輯的單純；代價是改一顆，整個 family 就要升版並重建整條 chain。無程式擋。
- **registry 前綴寫在取值點，不進 versions.conf。** registry 位址是部署常數，不是版本契約，混進版本檔會讓「這個檔管什麼」失焦。代價是換 registry 要改好幾處，見 [../AGENTS.md](../AGENTS.md)〈換 registry 要改好幾處〉。無程式擋。
- **manifest 用 echo 逐行拼。** 結構極簡、service 名都是安全字元，格式出錯的機會低；比較可能出錯的是清單與 registry 對不上。manifest 不加結構驗證，也不掛 push 護欄：後者會誤擋「先升版號、還沒建」的合法中間狀態。清單與 registry 對不上由 `task check:manifest` 擋下，它不在 `task lint` 與 push 護欄裡，發版時手動跑。
- **family-lint 只驗形狀，不驗指涉。** 不檢查第三方網址是否可達、checksum 是否正確，那些建置期自然會攔。唯一例外是 conf 文法那幾條：它們驗的是「被 `source` 時會不會執行別的東西」，位階等同機密掃描。conf 文法由 `lint:family` 擋下，`tests/test_family_lint.sh` 覆蓋。
- **靠正則認樣式的規則要配自我檢查。** 正則寫死字面時，規則可能「零匹配就全過」地靜默關閉。新增這類規則，都要想「匹配不到時是報錯還是靜默放行」。既有規則的自我檢查在 `lint:family`、`sync-lint.py`、`tests/test_cronjob.sh` 與 `.githooks/pre-push` 裡；新增規則時要不要配，無程式擋。
- **`lint:family` 不掛進 `build:image` 的前置條件。** 單一 family 的建置會因為不相干 family 的壞 conf 而失敗，煩擾大於防護。無程式擋。
- **同步規則保留 skopeo 原生格式。** 改掉等於重寫整個同步子系統。同理保留 manifest（對外契約）與 `sync/deploy/` 的 k8s manifest（kubectl 原生格式）。格式由 `sync-lint.py` 擋下。
- **`start.sh` 不設 `-e`。** 單一登入或單顆映像失敗不該中止整批，由重試與 `--keep-going` 容錯；最後仍失敗的映像累計起來，以 `exit 1` 讓叢集端的 Job 顯示失敗。由 `tests/test_sync_start.sh` 的登入失敗不中止斷言擋下。
- **憑證走 `secretGenerator`，真值檔放 `sync/secret/`。** kustomize 的 load restrictor 擋的是 `envs:`、`files:` 的裸檔案路徑，不擋目錄型 `resources:`，被指向的目錄自成一個 kustomize root。真值檔缺席時 `kubectl kustomize` 會失敗，刻意不讓佔位憑證進叢集。Secret 名與 CronJob 的引用由 `tests/test_cronjob.sh` 擋下（需要 kubectl）。
- **kustomize 入口放在 `sync/`，規則檔逐檔列。** `files:` 不支援 glob，也不准引用 kustomization 所在目錄以外的檔；kustomization 也不能放進 `repository/`，否則 `start.sh` 會把它當規則撈進去。規則檔漏列由 `tests/test_cronjob.sh` 的 ConfigMap 鍵斷言擋下（需要 kubectl）。
- **測試續用手寫 bash，放在 repo 根的 `tests/`。** `fixtures/stubs/` 靠 PATH 前置攔截 podman、skopeo、sudo，換 runner 要重新表達這套攔截。不對齊 app-services 的 Python 測試（它用 `python3 tests/<檔>.py` 逐支跑）：全部斷言得用 Python 重寫，這套攔截也要重做。無程式擋。
- **不修映像內容物腳本的 shellcheck 告警。** 那些腳本跑在容器內、沒有測試覆蓋，改動風險大於效益。無程式擋；`task lint` 的 shellcheck 不掃映像內容物。
- **系統佈建委派 provision，Dockerfile 只呼叫。** 二跳腳本的路徑固定是 `<distro>/<category>/<name>/<name>.txt`，Dockerfile 不內嵌等效的 apt、apk 或設定邏輯。代價是改佈建內容要去 provision 改，再升 `PROVISION_REF` 重建。Dockerfile 不內嵌佈建邏輯，無程式擋。引用浮動分支時，只有列在 `.githooks/forbidden-patterns.txt` 的分支名會被 push 護欄的 forbidden 掃描擋下。
- **容器專用的套件留在 Dockerfile，實體機也用的進 provision。** podman 映像自己裝 `fuse-overlayfs`，provision 的 `podman.txt` 只裝 `fuse`；qemu 沒有對應的 provision 腳本，套件直接寫在 Dockerfile。無程式擋。
- **testfile 走 rootful podman 與 bridge 網路。** rootless 的容器沒有可路由的 IP，建置機要 ssh 進容器只能走 rootful bridge。`--privileged` 給 podman-in-podman、qemu 與 systemd 類映像用，其他 family 照同一個樣板寫，不逐支判斷。代價見〈已知的結構性限制〉：容器名固定，不能並行。無程式擋。
- **taroko 收成 matrix，不是每個 K8s 版本一個 service。** 各格的 Dockerfile 只差一個版本值，分開放改一處要改每一份。代價是沒有 service 名，testfile 契約與 `SERVICE_VERSION` 都接不上。matrix 形態由 `lint:family` 擋下。
- **叢集端用 ConfigMap 掛規則與 `start.sh`，不從 GitLab clone。** 不必把 deploy token 放進 manifest、不會每晚自動跑未審查的 HEAD、執行映像不必帶 git 與 task。代價是規則改了要重新 apply。不再 git clone 由 `tests/test_cronjob.sh` 擋下（需要 kubectl）。
- **bigdata 走 ubuntu，不走 alpine 鏈。** Hadoop 的原生壓縮與加密庫綁 glibc，在 alpine 的 musl 上難以安裝。無程式擋。
- **landlord 以 root 起 sshd。** `log_client` 要建使用者、改 sudoers、卸載並改寫 serviceaccount 路徑，gateway 要批次建帳號並覆寫 `/etc/profile`，都要 root。其他 family 是 bigred 加 sudo。無程式擋。

## 5. 已知的結構性限制

- **沒有 CI。** 所有驗證在本機跑，加上 push 護欄。
- **testfile 不能並行。** 容器名固定 `repotest`，同一台機器同時跑兩支會撞名。
- **repo 只帶公鑰，映像層裡卻有私鑰。** `home/bigred/.ssh/` 只放 `authorized_keys`，部署用的私鑰由部署端以 K8s Secret 注入，Secret 名與掛載路徑本 repo 不定義。但跑過 provision `sshenv` 的層（alpine 的 sshd 層；rdp 兩顆經 `xfce.txt`、`lxqt.txt` 串 `aconfig`）會替 bigred 產一把無密碼 `id_rsa`，並寫進 `authorized_keys`。之後的 `COPY .ssh` 是合併，私鑰留在映像裡。能拉映像的人就拿得到。消除列在 [PROGRESS.md](PROGRESS.md)。
- **同版重建不可重現。** provision 釘得住腳本、釘不住套件，見 provision 的 `docs/ARCHITECTURE.md`〈已知的結構性限制〉。`BASE` 與 `PROVISION_REF` 都不動，隔一段時間重建再 push，同名 tag 的內容仍會變，下游靜默換映像。
- **bigred 的密碼沒有覆寫點。** 帳號、密碼與 UID 由 provision 的 `bigred.txt` 寫死，密碼等於帳號名，映像沒有環境變數或建置參數能改。部署端要在執行期改密碼，或只開金鑰登入。
- **taroko server 的 K8s 套件 patch 版浮動。** kubelet、kubeadm、kubectl 從 `pkgs.k8s.io` 的次版本套件庫裝，patch 由建置當下決定，`cri-docker-<次版>` 這個 tag 重建不保證相同。node 來自 `kindest/node`，釘到 patch。
- **bigdata HA 變體的 ssh 私鑰在映像層裡。** 建置期以 bigred 身分 `ssh-keygen` 給 sshfence 用，同一映像起的所有容器共用同一把，能拉映像的人就拿得到。
- **bigdata HA 的 JournalNode 只有兩個，且與 NameNode 同容器。** 任一個掉，edits 就寫不了；JobHistoryServer 也是單點。
- **bigdata 的日誌與 kafka 資料在 `/tmp`。** hadoop 與 hbase 的 log 目錄、hive 腳本的輸出與 kafka 的 `log.dirs` 都指向 `/tmp`，容器重啟即清空，除錯要趁容器還活著。
