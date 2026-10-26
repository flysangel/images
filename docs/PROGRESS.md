# images 進度

## 1. 目前狀態

- 標準驗證路徑：`task doctor` → `task lint` → `task test`，定義見 `AGENTS.md`〈完成定義〉。
- L1、L2 是綠的。`check-taskfile.py` 已實際檢查 Taskfile，不再略過。
- L3 未驗證：bigdata、landlord、rdp 等 family 還沒實建過，清單見〈待辦〉以「分批跑 `task ci:image`」開頭的那條。
- blocker：registry 上 `bigdata` 到 `landlord` 的映像鏈建不起來，見 `AGENTS.md`〈registry 上的映像鏈可能建不起來〉。

## 2. 待辦

有觸發條件的，句尾括號寫什麼時候做。

- 用當前釘的 provision 重建 registry 上的映像並發新版：步驟見 README〈升 PROVISION_REF〉。taroko 的 tag 不帶版號，重建會覆蓋 registry 上的既有 tag，動手前先決定做法。這也會修好 `landlord:tenant-hadoop` 對著 registry 建不起來的時間錯位
- 有 FROM 沒寫 tag、隱含 `latest`：`library/mariadb` 與 `minio/mc`，查法 `grep -n 'FROM .*\(mariadb\|minio/mc\)' infra/*/*.Dockerfile`。同步 CronJob 每晚把上游新版鏡進來，下次建置 base 就靜默換掉。在各 family 的 `versions.conf` 加頂層鍵（例如 `MARIADB_TAG`、`MC_TAG`）並在 FROM 使用。`minio/mc` 的同步規則目前只鏡 `latest`，要先改規則、同步一次才釘得了。等於換 base，整個 family 要升版並重建。同性質的還有 `infra/fbs/base.Dockerfile`：filebrowser 由上游 `get.sh` 的 `master` 分支裝最新版，沒釘版本或 checksum，改成釘 release URL 加 sha256，比照 alpine 的 `SEAWEEDFS_URL`
- `sync/kustomization.yaml` 的 `newTag` 與 `infra/alpine/versions.conf` 的 `SERVICE_VERSION` 是同值兩處，alpine 升版要同步改，沒有人執法。漏改時 CronJob 靜默跑在舊映像上。在 `tests/test_cronjob.sh` 加一條斷言比對兩者
- `sync/secret/secret.env` 的「值一律裸寫」沒有人執法：加了引號，引號會一起進 Secret，叢集端每晚登入失敗才顯現。在 `tests/test_cronjob.sh` 加一條斷言：產物 Secret 的值解碼後不得以引號開頭
- `bin/sync-lint.py` 用 Python 的 `re` 驗 tag regex，但 skopeo 用 Go 的 RE2。RE2 不支援 lookahead、lookbehind、反向引用，所以 Python 編得過不代表 skopeo 編得過，這條檢查有系統性的假陰性
- `tests/test_img.sh` 開頭自檢 `tests/fixtures/stubs/` 的執行位元，沒有就退場。做完刪 `AGENTS.md`〈直接跑 `test_img.sh` 前先確認 stub 有執行位元〉講 stub 的那段
- `tests/test_img.sh` 補 `build_args()` 缺鍵分支的 case：Dockerfile 宣告了光桿 `ARG`、值表沒有這個鍵時要失敗。`docs/ARCHITECTURE.md`〈設計取捨〉把這條列為 `img.sh` 擋下的約束，現在沒有測試釘住
- 分批跑 `task ci:image -- <family>` 補驗還沒實建過的 family：bigdata、landlord、rdp，以及 `fbs/base`、`open-webui/dbadm`、`gmm/mariadb`、taroko 的 `server`、`docker` 與 `node` 的第二個 stage。taroko 改跑 `bash infra/bin/img.sh ci taroko`。`lint:family` 只驗宣告與值表對得上，驗不到值進建置後的行為。先做第一條，或 bigdata 改用 `task build:image` 保留本機映像，不然 landlord 會撞 `AGENTS.md`〈registry 上的映像鏈可能建不起來〉
- testfile 只驗檔案存在、不驗權限：`bigdata/dtc-ha` 與 landlord 的 testfile 用 `ls` 加 `grep -q` 判定，`alpine/k8sadm` 與 rdp 的 `*-k8sadm` 只 `test -f`，誤植 `--chmod` 或漏 `--chown` 都抓不到。判定改用 `stat -c '%a %U'`
- `COPY` 的寫法不一致：`--chmod` 三位數與四位數並存（查法 `grep -h '^COPY' infra/*/*.Dockerfile | grep -oE -- '--chmod=[0-9]+' | sort | uniq -c`），與 `--chown` 併用時兩種順序都有。統一成四位數、固定順序，零行為變動
- `bin/family-lint.py` 加規則：每個 `COPY` 必帶 `--chmod`。當初刻意與 ARG 契約分開落地
- 確認 GitLab 上 svc_skopeo 的舊 deploy token 已撤銷，並輪換舊 repo 曾 commit 進 `.env` 的 Docker Hub、Red Hat、Quay 三組帳密：叢集已改跑本 repo 的同步 CronJob，但舊 token 與帳密的值都還在舊 repo 的 git 歷史裡，是否撤銷無法從本機確認
- `hbase-ha.Dockerfile` 只換了 hbstart、hbstop，`/bin/hdstart` 仍是從 `bigdata:hadoop` 繼承的單機版（format NameNode、起 SecondaryNameNode、不起 journalnode 與 zkfc），卻搭 HA 的 hadoop conf 且 CMD 先跑它；`hbase-ha.testfile` 驗不到。補 `hdstart-ha` 的 COPY，或把 CMD 改成不跑 hdstart
- `dtc-ha.Dockerfile` 的 hbase client conf 用單機版 `conf/hbase`，`hbase.rootdir` 釘 `${NAMENODE}:9820`；HA 叢集的 HDFS RPC 是 8020 加 nameservice，對不上。改 COPY `conf/hbase-ha`
- `conf/zookeeper/conf/zoo.cfg` 的 `dataDir` 寫死 `/home/bigred/zk`，沒用 `${HDUSER}`，`HDUSER` 不是 bigred 時 zk 資料不在 `hconfig` chown 的目錄裡。`bin/zkstart` 用 `grep -o '[0-9]'` 取主機名序號，兩位數會算錯，且每次啟動都追加 `server.N` 到 zoo.cfg
- hadoop 與 dtc-ha 裝的四個原生庫（zstd、libbz2、libssl、libisal）沒有驗收點。在 `hadoop.testfile` 與 `dtc-ha.testfile` 加 `hadoop checknative -a`
- `tenant-hadoop.testfile` 不驗 `envsubst` 與 `inotifywait`，`tenant.testfile` 有；兩者都是 `log_client` 的執行期相依，由 provision 的 `base.txt` 供給
- `log_client` 建 token Secret 後立刻用 jsonpath 讀 `ca.crt` 與 `token`，沒有等待迴圈；token controller 慢一步就把空字串寫進 serviceaccount 路徑
- `infra/landlord/bin/tenant/template/config.yaml` 被 COPY 進映像但 `log_client` 沒引用。刪檔，或補上用途
- open-webui 的四支 helper 直接寫 open-webui 的 `user`、`auth` 兩表，欄位清單綁 open-webui 的 schema 但沒記對應版本；`adduser.sh` 的兩次 INSERT 不在同一個 transaction，第二次失敗會留下半筆。在 `infra/open-webui/versions.conf` 記對應版本，INSERT 包進 transaction
- `infra/open-webui/lsuser.sh` 是四支 helper 裡唯一不檢查 `SQLITE_DB` 的，補上與其他三支相同的檢查
- 工作樹殘留未追蹤的 `infra/rdp/home/bigred/.ssh/id_rsa.pub` 與 `infra/taroko/home/bigred/.ssh/id_rsa.pub`（`.gitignore` 的 `id_rsa*` 擋下），Dockerfile 整目錄 COPY `.ssh`，這台機器建出的映像含它、乾淨 clone 不含。COPY 改成單檔 `authorized_keys`，或加 `.containerignore`
- sshd 的 `-e`（日誌導到 stderr 讓 `podman logs` 看得到）只有部分 CMD 帶，查法 `grep -rn 'sshd -D' infra`。統一加或統一拿掉
- `img.sh` 的 `pull` 對每個 ref 無條件拉，本機已有同名 tag 時會改指向拉下來的映像。加「本機已有就跳過」的守衛，做完刪 `AGENTS.md`〈build 後、push 前跑 `pull` 會蓋掉本機剛建的 tag〉
- `infra/bigdata/bin/hconfig` 跑 envsubst 前不驗變數，缺的靜默填空。渲染前比對 conf 樹用到的變數與環境，缺就 `Error:` 退場，做完縮 `AGENTS.md`〈bigdata 的 conf 樹是 envsubst 範本，缺變數不報錯〉
- `infra/alpine/base.testfile` 的 binary 名單沒有 tini，ubuntu 的有；tini 來自 provision，拿掉了建置照過、容器起不來
- 衍生顆（podman、qemu、s3cli、k8stools、k8sadm、knife）的 testfile 等完直接 ssh，沒有 sshd 兩顆那段「:22 沒在 listen 就 `[FAIL]`」的判定，失敗訊息是 ssh login failed，離根因遠
- `bin/sync-lint.py` 不驗同一規則檔內兩顆映像路徑最後一段相同；`skopeo sync` 不帶 `--scoped`，相同就互相覆蓋
- `infra/taroko/node.Dockerfile` 裝了 tini 但沒設 ENTRYPOINT 或 CMD，沿用 kindest/node 的進入點。決定刪套件或接上
- hive-ha、hbase-ha 也裝 `ncurses-bin psmisc`，只有 hadoop-ha 的 sshfence 用到 fuser。決定拿掉或留
- bigdata 六個 Dockerfile 的 `# hadolint ignore=` 沒有成對的警告原文行，不合 `~/.claude/rules/dockerfile.md`〈hadolint 註記〉，查法 `grep -B1 'hadolint ignore' infra/bigdata/*.Dockerfile`
- apt 清理有三種方言：ubuntu 系清 `/var/cache/apt/archives`，taroko 系清 `/var/lib/apt/lists/*`，bigdata 用 `apt` 不清理；`DEBIAN_FRONTEND=noninteractive` 只有兩檔帶。沒有一檔符合 `~/.claude/rules/dockerfile.md`〈RUN 寫法〉的四段寫法。`server.Dockerfile` 的 cri-dockerd 用 `dpkg -i`，缺相依不會自動補，可改 `apt-get install ./cri-dockerd.deb`
- 補 `docker.io/mintplexlabs/anythingllm` 的同步規則：runbook `apps/ai-stack.md` 的指令引用它，沒有 mirror 會直接拉 Docker Hub，撞匿名拉取的次數上限
- `img.sh` 驗 `PROVISION_REF` 的值是 `vX.Y.Z`，`config/versions.conf` 與 CLI 覆寫都驗：現在 `task build:image -- alpine sshd PROVISION_REF=main` 會建出 tag 帶版號、內容卻跟著 `main` 走的映像，護欄不掃 CLI
- 跑完 provision 腳本的 `RUN` 結尾刪 `sshenv` 產的 `/home/bigred/.ssh/id_rsa*`，並把 `authorized_keys` 還原成 repo 那份：alpine `sshd.Dockerfile`、rdp `xfce4.Dockerfile` 與 `lxqt.Dockerfile`。做完改 `docs/ARCHITECTURE.md`〈已知的結構性限制〉映像層私鑰那條
- `sync/repository/minio.yaml` 補收 `minio/minio` 的版本 tag：現在只鏡 `latest`，app-services 的 minio 與 juicefs 等這個才能改用 tag 釘
- `open-webui:dbadm` 沒有消費者：helper 綁 SQLite，app-services 的 openwebui 走 postgresql，用自己的 `sync.sh` 種 admin。決定刪這個 family，或改成接 postgresql

**以下有觸發條件才做：**

- `tests/test_img.sh` 補 `rmi` 的 case（下次改 `rmi` 之前）
- `build-all`、`test-all`、`ci-all` 補 task 包裝與測試，或刪掉這些子命令（下次改 dispatch 時）
- `tests/test_cronjob.sh` 的真產物斷言需要 kubectl，沒有 kubectl 時只跑自我檢查（想讓它進護欄或 CI 時）
- `family_service_version` 只驗非空、不驗值的形狀（有人繞過 `lint:family` 直接踩到時）
- `family-lint.py` 的 matrix 分支不驗條目內容（matrix 條目變複雜或改成自動產生時）
- taroko 的 docker 格不把版本傳進建置，`SERVERS_DOCKER` 只決定 tag（`SERVERS_DOCKER` 加第二格時）
- taroko 的 conf 取值與 `build_taroko` 的小重複抽共用（出現第 5 個消費者時）
- `ARG_ALIAS` 表在 `img.sh` 與 `family-lint.py` 各一份（別名超過 10 組，或第一次因漏同步出錯時）
- manifest 的 `registry_prefix` 欄位下游沒人讀（下次改 manifest 格式時決定留或砍）
- manifest 沒有 digest，registry 上的 tag 可被覆寫（發生 tag 覆寫事故時）
- gmm 的 maven、tomcat 補同步規則並改走自家 registry（要能離線建置，或上游限流打到時）
- taroko 三個 Dockerfile 補 testfile。要先擴 `docs/ARCHITECTURE.md`〈img.sh：協調層〉的 testfile 契約，現行只涵蓋非 matrix 且 tag 帶版號。斷言寫這些：起 `--privileged` 容器等 sshd、以 bigred 登入、`command -v` 驗 node 的 kubectl、kubeadm、kubelet、helm，server 的 dockerd、cri-dockerd、kubelet，docker 的 dockerd、containerd、docker；三顆以 systemd 或 kindest/node 當 PID 1，都要 `--privileged`（下次改 taroko 的 Dockerfile 之前）
- 上游 guacd 映像帶不帶 CJK 字型與 locale 沒查過；gmm 的 guacd 直接疊上游，自己沒有裝字型與 locale（有人回報終端中文顯示成方塊時）
- 審視 `infra/bigdata/`、`infra/landlord/` 的映像內容物（另開專項檢視時）
- `.gitattributes` 只對 `*.sh`、`*.py`、`versions.conf` 強制 LF，testfile 與無副檔名腳本沒有保護（有 CRLF 進庫，或下次改 `.gitattributes` 時）
- 在 umask 不同的機器上重建，驗證 `COPY --chmod` 都改到了（有第二台建置機時）
- 直接看一眼 `landlord:mariadb` 容器內的檔案權限（下次重建 landlord/mariadb 時）
