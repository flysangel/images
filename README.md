# images

映像供應層。一個 repo 兩個子系統：

- **`sync/`**：上游映像同步。依 `sync/repository/*.yaml` 的 tag regex 規則，用 `skopeo sync` 把上游 registry 的映像鏡到自家 registry。
- **`infra/`**：自建映像 family。`*.Dockerfile` 就是正本，沒有渲染步驟。版本值來自各 family 的 `versions.conf`，由 `infra/bin/img.sh` 組成 `--build-arg` 建置，依 `CHAIN` 的順序推上 registry。family 清單見 `ls infra/*/versions.conf`。

本 repo 產出版本清單 `docs/images-manifest.yaml` 給下游。**釘 `IMAGES_REF` 的下游不准手寫 image tag**，一律從本 repo 的 raw 路徑讀這份清單。上游只釘一個 repo：`provision`（建置期抓的二跳腳本）。

## 1. 安裝

本 repo 需要下面的命令。裝好後跑 `task doctor`，確認命令都在、種類也對。

| 需求 | 說明 |
|---|---|
| `task` | go-task v3，所有入口都走 `Taskfile.yaml` |
| `python3` 與 PyYAML | `bin/family-lint.py` 只用標準庫；`bin/sync-lint.py` 需要 PyYAML |
| `podman`、`skopeo` | 建置與推送，**全部呼叫走 `sudo`** |
| `shellcheck` | `task lint` 的靜態檢查 |
| `gitleaks` | push 護欄的機密掃描 |
| 對外網路 | 建置期抓 provision 的 raw 腳本與各種第三方來源，網址寫在各 family 的 `*.Dockerfile` 與 `versions.conf` |
| `kubectl` | 只有套用同步 CronJob 與 `tests/test_cronjob.sh` 的部分斷言需要 |
| `ssh`、`sshpass`、`jq` | testfile 用 `jq` 解 `podman inspect` 取容器 IP，再用 `sshpass` 登入容器。rdp 桌面層的 testfile 另要 `xfreerdp`，沒有就直接 `[FAIL]` |

push 護欄是本 repo 自帶的 `.githooks/pre-push`，由帳號層派工 hook 呼叫。沒有帳號層 hook 時，跑 `git config core.hooksPath .githooks`。

### 設定憑證

```bash
cp sync/secret/secret.env.example sync/secret/secret.env   # 填憑證，值一律裸寫、不加引號
```

`sync/secret/secret.env` 是 gitignored。要登入 registry 的 task 都讀它，設定見 `Taskfile.yaml` 的 `dotenv`。叢集端的 `secretGenerator` 也讀它。GHCR 那兩個鍵可以不填，`start.sh` 會匿名拉取，碰到 GitHub 限流再填。

## 2. 用法

`task` 印角色選單。`task dev`、`task ops`、`task release` 分別列出開發、維運、發版的 task，`task --list-all` 列出全部。第一次上手：

```bash
task lint                  # 秒級靜態檢查，不需網路
task try:image -- rdp   # 建 rdp 整條 chain 並跑煙霧測試
```

### 建映像

`<family>` 是 `infra/` 下有 `versions.conf` 的目錄名，`infra/bin/` 不是 family。只給 family 就依 `CHAIN` 走整條；給 service 就只做那一顆。

```bash
bash infra/bin/img.sh __dump_build_args rdp lxqt   # 印該顆會拿到的 --build-arg 值表
task try:image    -- rdp lxqt                      # 建置 → 煙霧測試，映像保留（主開發迴圈）
task build:image  -- rdp                           # 只建不測，映像保留
task smoke:image  -- rdp                           # 對已建映像跑 testfile，不建不刪
task ci:image     -- rdp                           # 建置 → 煙霧測試 → 清除，全過才清
task clean:image  -- rdp                           # 移除本機已建映像
```

- 已遷移到 `imgctl` 的 family（有 `infra/<family>/.imgctl` 的目錄）不能用這幾條指令，`img.sh` 與 `task *:image` 都會失敗。它們的值在 `catalog.yaml`，煙霧測試在 `infra/<family>/tests.yaml`，建置與測試由 `imgctl` 與 GitHub Actions 執行，見 `docs/ARCHITECTURE.md`。範例以仍走 `img.sh` 的 rdp 為準。
- 改了 base 層、要重建整條 chain，用 `task try:image -- <family>`。
- 給 service 時不會先建它的上游。本機 podman 沒有上游映像時 podman 會去 registry 拉，拉不到就失敗；先 `task pull:image -- <family>` 墊底，或建整條 chain。
- 單顆要覆寫契約值，`KEY=VAL` 必須搭 service：`task build:image -- rdp lxqt SERVICE_VERSION=v1.0.4`。KEY 只接受大寫字母、數字與底線，小寫會直接報錯。整條 chain 不支援覆寫。
- `taroko` 走 matrix，不接單一 service。`task ci:image -- taroko` 會先建完整個 matrix 才刪，磁碟峰值太大而被擋下；要建一格刪一格，改跑 `bash infra/bin/img.sh ci taroko`。
- 全 repo 逐一 family 測試是 `bash infra/bin/img.sh test-all`，沒有 task 包裝。

### 推上 registry

```bash
task push:image   -- rdp     # 先 build 讓本機有 tag，push 不建映像
task pull:image   -- rdp     # 拉 chain 上游墊底
task check:image  -- rdp     # skopeo inspect 線上查核映像存在
```

憑證由 task 的 `dotenv` 從 `sync/secret/secret.env` 注入，密碼走 `--password-stdin`、不落 argv。直接跑 `bash infra/bin/img.sh` 會繞過 `dotenv`，拿不到憑證。

### 上游同步

```bash
task mirror                 # 本機直接跑 skopeo sync
kubectl kustomize sync      # 印同步 CronJob 的最終 manifest，不套用
task apply:namespace        # 建 namespace svc（apply:cronjob 的前置）
task apply:cronjob          # kubectl apply -k 到叢集
```

叢集端是 namespace `svc` 的 CronJob。規則檔與 `start.sh` 打包成 ConfigMap 掛進去；叢集跑的是執行 `task apply:cronjob` 那份 checkout 的內容，與發版無關。規則改了要重新 apply 才會進叢集。拆除用 `kubectl delete -k sync`，沒有 task。

本機只想補跑一個 vendor 時，用 `YAML_REGEX=<檔名> task mirror`，例如 `YAML_REGEX=alpine.yaml`；`DEST=` 可改目的地，值要帶尾斜線。兩個都是 `start.sh` 自帶預設的環境變數。

### 加東西

- **加上游映像**：在 `sync/repository/` 建 `<vendor>.yaml`，檔名（去副檔名）就是目的地 repo 名。再把它加進 `sync/kustomization.yaml` 的 `skopeo-rules` 清單。上游主機是 `sync/bin/start.sh` 還沒登入過的，要在那裡補 login，並在 `sync/secret/secret.env.example` 與自己的 `secret.env` 補憑證鍵。
- **加映像 family**：在 `infra/<family>/` 放 `*.Dockerfile` 與 `versions.conf`，並把 family 名加進 `infra/bin/img.sh` 的 `FAMILIES_DEFAULT`。順序規則寫在那裡的註解。非 matrix 的 family，每個 service 都要放 `<service>.testfile`，否則 `task try:image` 會在 smoke 那步失敗；契約見 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)〈img.sh：協調層〉。

### 升 PROVISION_REF

改 `config/versions.conf` 的 `PROVISION_REF` 只影響之後的建置。過渡期已遷移的 family，值另在 `catalog.yaml` 的 `provision_ref`，兩處都要改成同值；不同值時 `imgctl lint` 會擋下（`task lint` 會跑它）。registry 上既有的映像要重建，才會用上新版 provision：

1. 用 `grep -l PROVISION_REF_IN infra/*/*.Dockerfile` 找出直接引用的 family。疊在它們上面的 family 要連帶重建。
2. 照各 family `versions.conf` 的 `UPSTREAM` 順序（例如 ubuntu → bigdata → landlord），每個 family 先升 `SERVICE_VERSION`。已遷移的 family 不靠 `versions.conf`：它的版本值在 `catalog.yaml`，tag 由 `imgctl` 決定。alpine 升版時 `sync/kustomization.yaml` 的 `newTag` 要同步改，理由見 [docs/PROGRESS.md](docs/PROGRESS.md)。taroko 是 matrix family，沒有 `SERVICE_VERSION`，tag 也不帶版號，重建並推送會覆蓋 registry 上既有的 tag。動手前先決定怎麼處理 taroko。
3. 對照 provision 新版的 `base.txt` 套件清單，更新 `infra/<family>/tests.yaml` 的 base 項目（尚未遷移的 family 改更新 `base.testfile`）。兩邊是同值兩處，沒有程式比對。
4. 用 `task try:image -- <family>` 重建整條 chain。已遷移的 family 不適用：改 push 到 `main`，由 `imgctl` 與 CI 重建。
5. 照〈推上 registry〉push，再照〈發版〉重生 manifest 並打 tag。已遷移的 family 的 push 由 CI 的 promote 完成。

### 升 alpine 或 ubuntu 基底

改該 family 的 `BASE`（已遷移的 family 例外：它的 `versions.conf` 已凍結，不要改；改 `catalog.yaml` 的值，由 `imgctl` 與 CI 重建），與改 `PROVISION_REF` 一樣，只影響之後的建置。tag 是 `<family>:<service>-<SERVICE_VERSION>`，`BASE` 改了而 `SERVICE_VERSION` 不動，重建推送會覆蓋 registry 上同名的 tag，manifest 不變、下游靜默換映像。

1. 升該 family 的 `SERVICE_VERSION`。
2. 用 `grep -l 'UPSTREAM=.*alpine' infra/*/versions.conf`（或 `ubuntu`）找出以它當上游的 family，照 `infra/bin/img.sh` 的 `FAMILIES_DEFAULT` 順序逐一升 `SERVICE_VERSION`。
3. 照〈升 PROVISION_REF〉從重建整條 chain 那步起做：重建、push、發版。

### 發版

```bash
task generate:manifest     # build + push 完成後重生版本清單
task check:manifest        # 發版守門：清單沒過期，承諾的 tag 線上都存在
git tag vX.Y.Z && git push origin vX.Y.Z
```

開發中間態（先升版號、還沒建）跑 `check:manifest` 本來就會紅，那是守門語意，不是壞掉。

### 跑測試

```bash
task lint                           # 四大文件、Taskfile、lint:family、同步規則、shellcheck
task test                           # tests/ 每一支，各支驗什麼見檔頭註解
task lint:family                    # 只驗各 family versions.conf 的文法、schema、FROM 拓撲、ARG 契約
```

改了什麼該跑哪幾支，見 [AGENTS.md](AGENTS.md)〈改了哪類檔要多驗什麼〉。

## 3. 文件導覽

| 文件 | 內容 |
|---|---|
| [AGENTS.md](AGENTS.md) | 開工必讀：ARG 契約、地雷、完成定義 |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | 版本契約、值表組裝、family 模型、sync、manifest、設計取捨 |
| [docs/PROGRESS.md](docs/PROGRESS.md) | 目前狀態：驗證路徑、各層燈號、blocker；還沒做的待辦 |
| `docs/images-manifest.yaml` | 給下游的版本清單，由 `task generate:manifest` 產生，不手寫 |

## 4. 貢獻

改動在 worktree 的分支上做。merge 前，[AGENTS.md](AGENTS.md)〈完成定義〉列的驗證要全部通過。

## 5. 授權

[Apache License 2.0](./LICENSE)。Copyright 2026 flysangel。
