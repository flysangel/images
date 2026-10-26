# `infra/landlord/` — 多租戶 SSH 平台樣板

5 個 service,`UPSTREAM="alpine bigdata"`。alpine 系租戶重用 `alpine:k8stools`,hadoop 租戶則 FROM `bigdata:dtc-ha`。

## 結構

```text
landlord/
├── versions.conf                 # SERVICE_VERSION=v1.0.3 + CHAIN(五顆) + UPSTREAM="alpine bigdata"
├── gateway.Dockerfile            # FROM alpine:sshd-${ALPINE_SERVICE_VERSION} + 跳板 profile + 批次建租戶帳號
├── logger.Dockerfile             # FROM alpine:base-${ALPINE_SERVICE_VERSION} + nc 監聽 log server
├── mariadb.Dockerfile            # FROM library/mariadb + initdb 建 history／inotify 表
├── tenant.Dockerfile             # FROM alpine:k8stools-${ALPINE_SERVICE_VERSION} + per-pod 使用者與 K8s 樣板
├── tenant-hadoop.Dockerfile      # FROM bigdata:dtc-ha-${BIGDATA_SERVICE_VERSION} + 同一套 log_client
├── <service>.testfile            # 對應 smoke test
├── bin/gateway/adduser           # 跳板:寫 /etc/profile 自動跳進租戶 pod,並批次建帳號
├── bin/logger/log_server         # nc -k -l 監聽 5566,解析事件寫入 MariaDB
├── bin/tenant/log_client         # 建立與 hostname 同名的使用者,送 history／inotify 事件
├── bin/tenant/template/          # role.yaml、secret.yaml 兩份 K8s 樣板;另有未被引用的 config.yaml,見 docs/PROGRESS.md
└── conf/mariadb/initdb/          # history 與 inotify 兩張表的 schema
```

`CHAIN` 是一維空白分隔;五顆彼此無依賴,全部 FROM 其他 family:

```conf
CHAIN="gateway logger mariadb tenant tenant-hadoop"
```

`*.Dockerfile` 就是正本,沒有渲染步驟——值由 `img.sh` 讀 `versions.conf` 組成 `--build-arg` 餵給 podman;契約鍵寫成光桿 `ARG`(無預設值)。

本 family 的契約鍵:`ALPINE_SERVICE_VERSION`、`BIGDATA_SERVICE_VERSION`(皆由 `UPSTREAM` 宣告的家族衍生)。本 family 的 `SERVICE_VERSION` 只用在 tag,不出現在任何 Dockerfile——所以它不是契約鍵、沒有對應的光桿 `ARG`。

## 三個角色怎麼串

```
使用者 ssh ──> gateway ──sshpass 自動跳──> tenant-<usertag>.<ns> pod
                                              │
                                              └── log_client 送 history／inotify 事件
                                                        ↓ nc 5566
                                                     logger ──INSERT──> mariadb
```

- **gateway** 是唯一對外的 SSH 入口,登入後由 `/etc/profile` 自動跳進對應租戶的 pod。
- **tenant** 每個 pod 建立與 `$(hostname)` 同名的使用者;`log_client` 依 `command -v apk` 分流 alpine(BusyBox `adduser` + `wheel` 群組)與 Debian 系(`useradd` + `sudo`)兩套帳號建立方式。
- **tenant-hadoop** 是 tenant 的 hadoop 版本,基底換成 `bigdata:dtc-ha`(內含完整 Hadoop 六組件),沿用同一套 log_client。
- **logger** 收事件寫 **mariadb**,兩張表的 schema 在 `conf/mariadb/initdb/`。

`bin/` 下的腳本是容器內服務腳本，自帶服務日誌格式，**不受**營運腳本的終端輸出慣例約束。

> `bin/gateway/adduser` 會批次建立租戶帳號且密碼等於帳號名——那是刻意的 lab 預設值,正式部署前必須覆寫。說明寫在該檔檔頭；不要「修」這類值的規則見 [`../../AGENTS.md`](../../AGENTS.md)〈不要做的事〉。

## Build

```bash
bash infra/bin/img.sh build landlord               # 整 family(五顆彼此獨立)
bash infra/bin/img.sh build landlord tenant        # 單一
bash infra/bin/img.sh __dump_build_args landlord gateway   # 印 --build-arg 值表(debug)
bash infra/bin/img.sh test landlord logger         # smoke test(image 必須先 build)
bash infra/bin/img.sh ci landlord                  # 磁碟友善:build+test 全部,全 pass 後 rmi 全部
```

建置前上游必須就位:`alpine:{base,sshd,k8stools}` 與 `bigdata:dtc-ha` 要先在本機或 registry 有對應 tag,否則 podman 會嘗試 pull 而失敗。用 `bash infra/bin/img.sh pull alpine` 先拉墊底。

## 升級

改 `versions.conf` 的 `SERVICE_VERSION` 後重 build。上游 alpine 或 bigdata 升版時,本 family 不必改任何 FROM 行——版本值由 `UPSTREAM` 宣告的家族自動衍生,只要重 build 就會指向新的上游 tag。
