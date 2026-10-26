# AGENTS.md

寫給 AI agent 的 images 作業指引。只收 images 專屬、而且跨檔的事。只跟單一檔案有關的坑寫在該檔註解；改 `infra/bin/img.sh`、`bin/family-lint.py` 前，先讀要改的函式上方的註解。

## 1. 30 秒定位

- 映像供應層。`sync/` 鏡上游映像，`infra/` 建自家 family 的映像，兩者都推 `quay.io/flysangel`。
- 值的唯一來源是各 family 的 `versions.conf`（過渡期例外：alpine 的值在 `catalog.yaml`）。`infra/bin/img.sh` 把它組成 `--build-arg` 交給 podman，沒有渲染步驟，`infra/<family>/*.Dockerfile` 就是正本。
- 本 repo 產出 `docs/images-manifest.yaml`，是釘 `IMAGES_REF` 的下游唯一的 image tag 來源。manifest 一發佈，下游就照它取 tag，所以改動的代價在下游。消費者範圍見 `docs/ARCHITECTURE.md`〈定位與邊界〉。
- 上游只釘 `provision`，版本在 `config/versions.conf` 的 `PROVISION_REF`。過渡期 alpine 的值另在 `catalog.yaml` 的 `provision_ref`，兩處都要改，不同值時 `imgctl lint` 擋下。
- push 護欄是本 repo 自帶的 `.githooks/pre-push`，由帳號層派工 hook 呼叫。兩層怎麼串見 `~/.claude/rules/githooks.md`〈兩層 hook 怎麼串〉。

## 2. 開工

1. 讀 `docs/PROGRESS.md`〈目前狀態〉。
2. 跑 `task doctor`。
3. 跑 `task lint` 與 `task test`。

基準是紅的時，先修好，再開始新工作。

### 直接跑 `test_img.sh` 前先確認 stub 有執行位元

```bash
for s in podman skopeo sudo; do [ -x "tests/fixtures/stubs/${s}" ] || echo "stub 失效：${s}，別跑 test_img.sh"; done
```

`tests/test_img.sh` 靠 `tests/fixtures/stubs/` 攔截 podman、skopeo、sudo。`task test` 的 precondition 會擋下失效的 stub。直接跑 `bash tests/test_img.sh` 時**不會警告**，會呼叫真的 `sudo podman`：實際建出映像、寫 `/tmp/test_img_podman.log`。

### 從 worktree 跑 sync 相關的東西前，先複製 `secret.env`

`sync/secret/secret.env` 是 gitignored，worktree 的檢出不帶它。`kubectl kustomize sync`、`task mirror` 與 `task apply:cronjob` 都要它，先從主工作樹複製一份進 worktree 的 `sync/secret/`。`tests/test_cronjob.sh` 不用：缺這個檔時，它在暫存樹改用 `.example` 的值。

### 光桿 `ARG` 就是契約值

| 寫法 | 語意 | `img.sh` 行為 |
|---|---|---|
| `ARG X`（光桿，無預設值） | **契約值**，受 `versions.conf` 管轄 | 必傳 `--build-arg X=…`；值表沒有此鍵就立刻失敗 |
| `ARG X=y`（帶預設值） | Dockerfile 自有的建置期變數 | 不傳 |

- **`ARG` 不跨 stage**：stage 內文要用契約鍵，該 stage 必須再宣告一次光桿 `ARG X`。忘了的話 `${X}` 靜默展開成空字串，建置照樣成功。
- **契約鍵不得與 `ENV` 鍵同名**：父映像的 `ENV X` 會蓋掉同名的光桿 `ARG X`。所以 provision 版本一律寫成 `ARG PROVISION_REF_IN` 加 `ENV PROVISION_REF=${PROVISION_REF_IN}`。
- 這幾條與 ARG 名的格式都由 `task lint:family` 擋，規則細節見 `docs/ARCHITECTURE.md`〈治理層〉。

### Dockerfile 的寫法

- **`COPY` 一律帶 `--chmod`**（`--from` 的 stage 間複製除外）。不帶的話權限跟著建置機的 umask 走，而 git 只追蹤執行位元，`0600` 與 `0644` 對它一樣，`git diff` 看不出來。有 shebang 的腳本與目錄樹用 `0755`，資料單檔用 `0644`。
- **目錄樹不能用 `0644`。** `--chmod` 對目錄樹一律套同一個模式，`0644` 會讓子目錄失去執行位元，任何人都進不去。代價是設定檔帶上無意義的執行位元，不要「順手修正」。
- **`home/<user>/.ssh` 用 `0700`，含密碼的設定檔用 `0600`。** 統一成 `0755` 會讓 SSH 目錄全世界可讀。
- **global ARG 不得插進 `# hadolint ignore=` 與它的目標指令之間。** 該註解只對緊接的下一個指令生效。ARG 貼在 `FROM` 正上方，抑制目標就變成 `ARG`。受影響的檔用下面這段重算：

```bash
for f in infra/*/*.Dockerfile; do
  awk -v F="$f" '/^[[:space:]]*#[[:space:]]*hadolint ignore=/{h=NR;next} /^[[:space:]]*FROM /{if(h&&NR==h+1)print F": L"NR} /^[[:space:]]*$/{next} {h=0}' "$f"
done
```

- 引用 Docker Hub 一律用光桿 `ARG UPSTREAM_DOCKER` 加 `${UPSTREAM_DOCKER}`。引用 provision 腳本一律 `raw/${PROVISION_REF}/`，不寫浮動分支。
- **經 `${REGISTRY_PREFIX}` 引用同步進來的上游映像時，path 與 tag 照上游寫**，例如 `library/alpine:3.21.3`、`kindest/node:v1.34.0`。sync 以規則檔名當 repo 名、原樣搬 tag，見 `docs/ARCHITECTURE.md`〈sync：上游同步〉。
- **`COPY` 不吃 `USER`，檔案預設歸 root。** 放進使用者家目錄且權限是 `0600` 或 `0700` 的檔要帶 `--chown`，否則該使用者讀不到。`--from` 搬進來的單一可執行檔先落 `/tmp`，再 `install -o root -g root -m 0755` 設權限。
- **`COPY` 目錄是合併，不是取代。** 疊 HA 版 conf 或換啟停腳本前，先 `rm` 繼承來的單機版，否則舊檔留在映像裡。
- **build context 是整個 `infra/<family>/`**，同 family 全部 service 共用，`COPY` 的來源路徑相對 family 根，不是相對 Dockerfile。repo 沒有 `.containerignore`，整個目錄每次都送進 context。
- **Ubuntu 系的 sshd 要在 CMD 自建 `/run/sshd`**，alpine 系不用。現有寫法有 `mkdir -p` 與 `install -m 0755 -d` 兩種，查法 `grep -rn 'run/sshd' infra`。
- **bigdata 每顆同時寫 `/etc/profile.d/<組件>-env.sh` 與 `ENV`。** ssh 登入的 login shell 只讀 profile.d，`podman exec` 與 CMD 只讀 ENV，刪一邊壞一邊。

## 3. 地雷

### 不能直接 `podman build`

值全部由 `--build-arg` 供給。單獨 build 某個 Dockerfile，光桿 ARG 會展開成空字串：`FROM ${REGISTRY_PREFIX}/…` 變成空的，錯誤訊息是 `Error: determining starting point for build: no FROM statement found`，離根因很遠。另一個後果是 pipefail：podman 預設的 OCI 格式會忽略 `SHELL`，`curl … | bash` 在 curl 失敗時照樣建成映像；`pbuild` 固定帶 `--format docker` 才讓 `SHELL` 生效。**所有建置一律經 `img.sh` 或 `task image:*`。**已遷移的 family 例外：它們改走 `imgctl`，見〈已遷移的 family 改由 imgctl 建置〉。要看某顆會拿到哪些值（已遷移的 family 不適用，改看 `imgctl plan`）：

```bash
bash infra/bin/img.sh __dump_build_args rdp lxqt
bash infra/bin/img.sh __dump_build_args taroko node KUBERNETES_VERSION=v1.34.0
```

### `versions.conf` 會被 `source`，等同可執行程式碼

`img.sh` 以 `. versions.conf` 取值。**含空白的值必須加雙引號**，否則 bash 會把它當成「變數設定加指令」，真的執行那個指令：

```conf
CHAIN=base sshd podman      # 錯：實際執行了系統的 sshd，CHAIN 事後是 unset
CHAIN="base sshd podman"    # 對
```

`task lint:family` 擋這條，也擋未閉合引號與值含 `$` 或反引號。

### 已遷移的 family 改由 imgctl 建置

哪些 family 已遷移：看 `infra/*/.imgctl`，有這個標記檔的 family 就是。這些 family 只能經 `imgctl` 與 GitHub Actions 建置。`img.sh` 與 `task build:image` 不適用：它們的 Dockerfile，FROM 已改成光桿 `*_IMAGE`，沒有 `imgctl` 供值就建不起來。其他 family 照舊用 `img.sh`。

已遷移 family 的 `versions.conf` 凍結，不要改。它只供尚未遷移的 family 取上游值。已遷移 family 自己的值看 `catalog.yaml`。

### registry 上的映像鏈可能建不起來

`bigdata` 到 `landlord` 這條鏈在 registry 上有時間錯位：舊的 `bigdata:dtc-ha` 帶著舊版 provision 寫的 `/etc/profile.d/task-env.sh`，撞上新版守衛。對著 registry 現況建 `landlord:tenant-hadoop` 會失敗，錯誤是 dash 的 `Syntax error: "(" unexpected`。這不是本 repo 釘錯版：本機重建 `bigdata:jdk` 與 `bigdata:dtc-ha` 後就能過。根治列在 `docs/PROGRESS.md`。

### 換 registry 要改好幾處

registry 位址 `quay.io/flysangel` 寫在取值點，不進 `versions.conf`：`infra/bin/img.sh` 的 `REGISTRY_PREFIX` 預設值、`sync/bin/start.sh` 的 `DEST`（以字串相接組目的地，值要保留尾斜線）、`sync/kustomization.yaml` 的 `newName`。過渡期另有三處：`catalog.yaml` 的 `registry`、`.github/workflows/images.yml` 的 promote 目的地、`.github/workflows/build-batch.yml` 的 `ghcr.io/flysangel/images-staging`。`tests/test_cronjob.sh` 與 `tests/test_sync_start.sh` 也寫了字面值。漏改任一處，建置、同步或測試就會指向舊 registry。下游 app-services 每個服務的 `images:` 也寫死 registry 位址。app-services 不讀 manifest，換 registry 時要另外通知它改 `images:`。查法：

```bash
grep -rn 'quay.io/flysangel' --include='*.sh' --include='*.yaml' . | grep -v -e fixtures -e images-manifest
```

### 別寫出會被護欄擋下的字面

護欄的 forbidden 掃描擋 Docker Hub 主機名後接路徑的字面，以及 `raw/` 後接浮動分支名的引用。`infra/`、`sync/`、`Taskfile.yaml` 都在掃描範圍，註解也算。擋哪些樣式見 `.githooks/forbidden-patterns.txt`，**不要把樣式複製進其他受掃描的檔**。

### `hadolint ignore=` 沒有對應的工具

不少 Dockerfile 帶 `# hadolint ignore=` 註解，但本機沒裝 hadolint，沒有 lint 入口，push 護欄也不跑它。註解只是給人看的意圖說明，沒有任何工具會檢查這些註解。自家的 `alpine:k8stools`、`alpine:k8sadm` 與 rdp 的 `*-k8stools`、`*-k8sadm` 映像內有 hadolint（provision 的 `k8stools.txt` 裝的），要跑就用容器跑。

### build 後、push 前跑 `pull` 會蓋掉本機剛建的 tag

`task pull:image` 對每個 ref 無條件 `podman pull`。拉到與本機同名的 tag 時，本機那個 tag 改指向拉下來的映像，剛 build 還沒 push 的那顆就失去 tag。先 push 再 pull，或只 pull 上游 family。

### 桌面層的 CMD 與 `k8sadm-entry.sh` 是同一段啟動序兩處

`infra/rdp/xfce4.Dockerfile`、`lxqt.Dockerfile` 的 CMD 與 `infra/rdp/bin/k8sadm-entry.sh` 寫同一段 dbus、xrdp、sshd 啟動序；alpine 的 `sshd.Dockerfile` CMD 與 `infra/alpine/bin/k8sadm-entry.sh` 同理。改一邊要同步另一邊，否則 k8sadm 映像的行為與桌面層分叉。

### taroko 加格子前，上游映像要先同步進自家 registry

`node.Dockerfile` 的 FROM 是 `${REGISTRY_PREFIX}/kindest/node:<版本>`，server 兩顆是 `${REGISTRY_PREFIX}/jrei/systemd-ubuntu:<版本>`。`NODES` 加一格或換 systemd-ubuntu 版本前，`sync/repository/kindest.yaml`、`jrei.yaml` 的同步要先跑過一次，否則 FROM 拉不到。

### 映像內容物的執行期相依來自 provision，不是本 repo 的 Dockerfile

bigdata 與 landlord 的腳本在執行期用 `ping`、`envsubst`、`inotifywait`、`sshpass`、`jps`，ENTRYPOINT 用 `tini`。除了 `jps` 來自 JDK，其餘都由 provision 的 `base.txt` 裝進 base 層，本 repo 的 Dockerfile 多數不裝。provision 砍掉套件時建置照過、容器起不來，testfile 只有部分顆驗這些指令。

### bigdata 的 conf 樹是 envsubst 範本，缺變數不報錯

`infra/bigdata/conf/` 底下的 XML 與 properties 由 `hconfig` 在執行期 envsubst，要哪些環境變數用 `grep -rhoE '\$\{[A-Z_]+\}' infra/bigdata/conf infra/bigdata/bin | sort -u` 查。沒設的變數靜默填成空字串，錯誤要到 daemon 起不來才看得到；`WAIT` 沒設則 `sleep ""` 直接報錯。`conf/hadoop-ha/` 一份被多顆共用，改一處動好幾顆，查法 `grep -l 'conf/hadoop-ha' infra/bigdata/*.Dockerfile`。單機 conf 的 NameNode RPC 是 9820，HA conf 是 8020 加 nameservice，client conf 混用就連不上。

### landlord 的名字、線路格式與權限需求寫死在腳本裡

gateway 帳號名、tenant pod 的 hostname、tenant 內建的使用者、namespace 四者必須同名：`bin/gateway/adduser` 把登入跳轉寫成 `<user>@<user>.${USERTAG}.${NS}`，`bin/tenant/log_client` 用 hostname 建使用者與 namespace。logger 與 tenant 之間的 port 與欄位切法在 `log_server` 與 `log_client` 各寫一份，`HISTTIMEFORMAT` 前後的分隔字元決定 `cut -f` 的欄位號。`log_client` 在 pod 內建 namespace、ServiceAccount、Role 與 Secret，再 `umount` 原 serviceaccount 路徑寫入新憑證。這要 pod 原本的 SA 有叢集級權限，也要 pod 能 umount。少一樣 `log_client` 就半途失敗，sshd 照起。

### 從 worktree 跑 `task apply:cronjob` 會把未審查的內容送進叢集

叢集跑的是執行 apply 那份 checkout 的規則與 `start.sh`。正式套用一律從 `main` 執行。

## 4. 完成定義

下面各層全部通過，才算完成：

- L1：`task lint`。四大文件、Taskfile、`lint:family`、同步規則與 shellcheck，每道都要 exit 0。
- L2：`task test`。`tests/` 每支都要 `0 failed`、exit 0。沒有 kubectl 時，`tests/test_cronjob.sh` 的真產物斷言印 `[SKIP]`，`task test` 照樣綠。改了 `sync/` 時，在有 kubectl 的機器重跑，確認沒有 `[SKIP]`。
- L3：`task try:image -- <family> <service>` 實建並跑 testfile。只在改了 Dockerfile、`versions.conf` 或映像內容物時才跑。理由：L1 與 L2 不實際建置，看不到值進了建置之後的效果。

### 改了哪類檔要多驗什麼

下表寫改了哪類檔時要看哪一支的輸出。表中的 lint 與 `tests/` 都已接進 `task lint`、`task test`。`__dump_build_args`、`task try:image` 與 manifest 的 diff 要另外跑。`task lint` 的 shellcheck 只掃 `Taskfile.yaml` 列出的檔。新增腳本時，把它加進 `lint` 的清單。

| 改了什麼 | 跑什麼 |
|---|---|
| family 的 `versions.conf` 或 `*.Dockerfile` | `task lint:family`；看值表用 `__dump_build_args`（已遷移的 family 不適用，改看 `imgctl plan`）；真要確認建得起來只有 `task try:image -- <family> <service>`。alpine 升版再跑 `bash tests/test_cronjob.sh`，`sync/kustomization.yaml` 的 `newTag` 要同步改。過渡期已遷移的 family，版本值在 `catalog.yaml`，它的 `versions.conf` 已凍結 |
| `config/versions.conf` | 沒有程式驗。鍵名與 `vX.Y.Z` 值靠人維持 |
| `infra/bin/` | `bash tests/test_img.sh`，直接跑前先確認 stub 有效 |
| `bin/family-lint.py` | `bash tests/test_family_lint.sh` |
| `sync/kustomization.yaml`、`sync/deploy/`、`sync/secret/`，或新增、刪除 `sync/repository/*.yaml` | `bash tests/test_cronjob.sh` |
| `sync/repository/*.yaml` 的內容 | `python3 bin/sync-lint.py sync/repository/*.yaml`（從 repo 根跑） |
| `sync/bin/start.sh` | `bash tests/test_sync_start.sh` 與 `bash tests/test_sync_lint.sh` |
| 任何腳本 | `shellcheck -S warning <檔>`。`task lint` 清單裡的腳本要維持零告警 |
| manifest 的邏輯 | `MANIFEST_OUT=/tmp/x.yaml bash infra/bin/img.sh manifest`，導到暫存檔再 diff 正本，不要直接覆蓋 |

懷疑 hook 沒在跑時，push 前手動跑一次 push 護欄，寫法見 `~/.claude/rules/githooks.md`〈直接跑 `pre-push` 不餵 stdin 會得到假綠燈〉。改了 `.githooks/`、`bin/check-*.py`、`bin/family-lint.py` 或 `bin/sync-lint.py`，照 `~/.claude/rules/githooks.md`〈改了 `.githooks/` 底下任何東西〉再跑一次真的 hook。這四類都是 hook 的輸入。hook 用的是主工作樹那一份，原因見 `~/.claude/rules/githooks.md`〈在 worktree 裡 push 驗不到你剛改的 hook〉。分支同時改 lint 與被 lint 的檔時，在 worktree 跑 `task lint` 是綠的，push 仍可能被主工作樹的舊 lint 擋下。

## 5. 不要做的事

| 不要 | 為什麼 |
|---|---|
| 「修」入庫的 lab 預設憑證，或新增同類明文 | 那些是刻意的 demo 值，各檔註解有說明。正式部署前要覆寫；寫部署文件時標出覆寫點 |
| 把 `CHAIN` 或 `FAMILIES_DEFAULT` 改成字母序 | 它們是建置依賴序，排序會讓建置拉不到上游映像 |
| 為了讓 `check:manifest` 變綠而提前重生 manifest | 會把 registry 還沒有的 tag 寫進下游契約 |
| 給沒有 tag 的 FROM 順手加 tag | 等於換 base，整個 family 要升版並重建，見 `docs/PROGRESS.md` |
| 改 `BASE` 或升上游 family 的版本，卻不升本 family 的 `SERVICE_VERSION` | tag 不變、內容變了，重建推送會覆蓋 registry 上的同名 tag，manifest 不動而下游靜默換映像。步驟見 `README.md`〈升 alpine 或 ubuntu 基底〉 |
| 把 `COPY` 的 `0700`、`0600` 統一成 `0755` | SSH 目錄與含密碼的檔會變成全世界可讀 |
