# `infra/bigdata/` — Hadoop 系譜樣板

Hadoop 生態 12 個 service，依繼承鏈建置。套件一律取自官方源並驗 checksum。本 family 已遷到 `imgctl`：值在 `catalog.yaml`，煙霧測試在 `tests.yaml`，建置與測試由 `imgctl` 與 GitHub Actions 執行，不用 `img.sh`。

## 結構

```text
bigdata/
├── jdk.Dockerfile            # FROM ${UBUNTU_SSHD_IMAGE}，加 Temurin JDK8
├── zookeeper.Dockerfile      # FROM ${BIGDATA_JDK_IMAGE}
├── kafka.Dockerfile          # FROM ${BIGDATA_JDK_IMAGE}
├── hadoop.Dockerfile         # FROM ${BIGDATA_JDK_IMAGE}
├── hbase.Dockerfile          # FROM ${BIGDATA_HADOOP_IMAGE}
├── hive.Dockerfile           # FROM ${BIGDATA_HADOOP_IMAGE}，加 MariaDB JDBC
├── spark.Dockerfile          # FROM ${BIGDATA_HADOOP_IMAGE}
├── hadoop-ha.Dockerfile      # FROM ${BIGDATA_HADOOP_IMAGE}
├── hive-ha.Dockerfile        # FROM ${BIGDATA_HIVE_IMAGE}
├── hbase-ha.Dockerfile       # FROM ${BIGDATA_HBASE_IMAGE}
├── hiveDB.Dockerfile         # FROM ${LIBRARY_MARIADB_IMAGE}，加 hive metastore schema patch
├── dtc-ha.Dockerfile         # FROM ${BIGDATA_JDK_IMAGE}，平鋪重組全部六個組件（不 FROM hadoop）
├── tests.yaml                # 煙霧測試規格
├── smoke-<service>.sh        # 各顆的煙霧測試，由 tests.yaml 的 script 呼叫
├── smoke-run.sh              # 各顆共用：容器內以 login shell 跑指令，比對輸出
├── versions.conf             # 凍結，只供尚未遷移的 landlord 取 BIGDATA_SERVICE_VERSION
├── bin/                      # 容器內服務腳本，COPY 進 /bin
├── conf/                     # 各組件設定樹，COPY 進 /conf/<版本目錄>，由 hconfig 覆蓋到 /opt
├── .imgctl                   # 已遷移標記
└── README.md
```

FROM 的 ARG 名由 `imgctl` 依 family 與 service 名產生，例如 `hadoop` 得 `BIGDATA_HADOOP_IMAGE`。各顆的上層見上面的結構樹。同一層的 service 彼此獨立：

```text
ubuntu:sshd → jdk → [zookeeper, kafka, hadoop, dtc-ha] → [hbase, hive, spark, hadoop-ha] → [hbase-ha, hive-ha]
上游 mariadb → hiveDB
```

本 family 的契約鍵是各組件的 `<組件>_VERSION`、`<組件>_URL`、checksum 鍵，以及 `JDBC_*`，值在 `catalog.yaml` 的 bigdata `values`。`<組件>_VERSION` 的值是解壓後的目錄名（例如 `hadoop-3.4.0`），不是單純的版本號：Dockerfile 用它組 `/opt/<目錄名>` 與 `/conf/<目錄名>`，`hconfig` 靠兩者同名把設定對到組件。

tag 分三類：

- `jdk`、`zookeeper`、`kafka`、`hadoop`、`hbase`、`hive`、`spark` 是甲類，tag 是 `<service>-<組件版本>`，例如 `hadoop-3.4.0`。
- `hiveDB` 是乙類，tag 由建好的映像內 `mariadbd --version` 決定。
- `hadoop-ha`、`hive-ha`、`hbase-ha`、`dtc-ha` 是丙類，tag 是 `<service>-vX.Y.Z`，下一版由 `imgctl plan` 算出。

## bin/ 的角色分派

容器內服務腳本,每個組件一組 start／stop:

| 腳本 | 用途 |
|---|---|
| `hconfig` | 共用 bootstrap:建 `/run/sshd`,把 `/conf` 下的設定覆蓋到對應的 `/opt/<組件>` |
| `hdstart` / `hdstop`(及 `-ha`) | HDFS + YARN |
| `hbstart` / `hbstop`(及 `-ha`) | HBase |
| `hvstart` / `hvstop` | Hive metastore + hiveserver2 |
| `zkstart` / `zkstop` | ZooKeeper |
| `kfstart` / `kfstop` | Kafka |
| `hvrc` | 為每個 `/home/*` 寫 per-user `~/.hiverc` |
| `hvsql` | beeline 連線便利包裝 |

共同慣例:`log()` 時間戳輸出、`waitserver()` 輪詢等待、用 `$(hostname)` 比對角色環境變數(`WORKERNODE`／`HBASE`／`ZOOKEEPER`／`KFBROKER`／`HIVEMETASTORE`／`HIVESERVER2` 等)決定該起哪些 daemon、`jps -m | grep -q` 判活。

這層屬容器內服務日誌，自帶 `date LEVEL msg` 格式，**不受**營運腳本的 `Error:／Success:／Info:` 終端輸出慣例約束。

## Build

看值表與 tag：

```bash
go run ./cmd/imgctl plan
```

上層重建時，疊在它上面的 service 跟著重建。`ubuntu:sshd` 重建時，除了 `hiveDB`，整個 family 都重建。

## 煙霧測試

- 每顆都走 script，`imgctl` 以 sleep 起容器，不跑 CMD，也不驗 ssh。
- 腳本在容器內用 `bash -lc` 跑指令。login shell 才讀 `/etc/profile.d/<組件>-env.sh`，所以版本字串的比對也驗到 profile.d。
- 每顆比對的樣式寫在各自的 `smoke-<service>.sh`。

## 升級

升組件版本：

1. 改 `catalog.yaml` 的 bigdata `values` 裡該組件的 `_VERSION`、`_URL` 與 checksum 鍵。三者要同時改。
2. 該組件是甲類時，改同一個 service 的 `version`。
3. 改 `smoke-<service>.sh` 比對的版本字串。疊在它上面、也比對這個版本的 service 一起改，查法 `grep -n '<舊版本>' infra/bigdata/smoke-*.sh`。

checksum 一律取自上游官方發佈的校驗檔。上游只發 md5 時，用本地下載算出 sha256，與上游 md5 交叉驗證後寫入，並在 `catalog.yaml` 的註解寫明來源。

`versions.conf` 凍結，升級時不要改。landlord 遷到 `imgctl` 後就刪掉它。
