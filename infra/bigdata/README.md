# `infra/bigdata/` — Hadoop 系譜樣板

Hadoop 生態 12 個 service 依繼承鏈 build,`UPSTREAM=ubuntu`。套件一律官方源 + checksum,版本與網址是 `versions.conf` 的頂層鍵。

## 結構

```text
bigdata/
├── versions.conf             # SERVICE_VERSION=v1.0.1 + CHAIN(一維十二顆) + UPSTREAM=ubuntu + 組件 DIR/URL/CHECKSUM 鍵
├── jdk.Dockerfile            # FROM ubuntu:sshd-${UBUNTU_SERVICE_VERSION}(跨家族進入點) + Temurin JDK8
├── zookeeper.Dockerfile      # FROM bigdata:jdk
├── kafka.Dockerfile          # FROM bigdata:jdk
├── hadoop.Dockerfile         # FROM bigdata:jdk
├── hbase.Dockerfile          # FROM bigdata:hadoop
├── hive.Dockerfile           # FROM bigdata:hadoop + MariaDB JDBC
├── spark.Dockerfile          # FROM bigdata:hadoop
├── hadoop-ha.Dockerfile      # FROM bigdata:hadoop
├── hive-ha.Dockerfile        # FROM bigdata:hive
├── hbase-ha.Dockerfile       # FROM bigdata:hbase
├── hiveDB.Dockerfile         # FROM library/mariadb + hive metastore schema patch
├── dtc-ha.Dockerfile         # FROM bigdata:jdk,平鋪重組全部六個組件(不 FROM hadoop)
├── <service>.testfile        # 對應 smoke test
├── bin/                      # 18 支容器內服務腳本,COPY 進 /bin
└── conf/                     # 各組件設定樹,COPY 進 /conf/<版本目錄>,由 hconfig 覆蓋到 /opt
```

`CHAIN` 是一維空白分隔的建置序。原本 YAML 時代的六層分組邊界零消費、已取消,同層彼此獨立的資訊改由這裡的圖說明:

```
[jdk] → [zookeeper, kafka, hadoop] → [hbase, hive, spark] → [hadoop-ha, hive-ha, hbase-ha] → [hiveDB] → [dtc-ha]
```

`*.Dockerfile` 就是正本,沒有渲染步驟——值由 `img.sh` 讀 `versions.conf` 組成 `--build-arg` 餵給 podman;契約鍵寫成光桿 `ARG`(無預設值)。

本 family 的契約鍵:`SERVICE_VERSION`(同家族 FROM)、`UBUNTU_SERVICE_VERSION`(跨家族,由 `UPSTREAM=ubuntu` 衍生),以及組件鍵 `JAVA_URL` / `JAVA_SHA256`、`HADOOP_*`、`HIVE_*`、`HBASE_*`、`SPARK_*`、`KAFKA_*`、`ZOOKEEPER_*`、`JDBC_*`。

> 組件的版本鍵有一組**別名**:Dockerfile 側寫 `ARG <組件>_VERSION`,值取自 `versions.conf` 的 `<組件>_DIR`(解壓後的目錄名)。對應表在 `infra/bin/img.sh` 的 `ARG_ALIAS` 與 `bin/family-lint.py` 各一份,改一邊要改兩邊。

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

```bash
bash infra/bin/img.sh build bigdata                # 整 family,依 chain 順序
bash infra/bin/img.sh build bigdata hive           # 單一
bash infra/bin/img.sh __dump_build_args bigdata hadoop   # 印 --build-arg 值表(debug)
bash infra/bin/img.sh test bigdata jdk             # smoke test(image 必須先 build)
bash infra/bin/img.sh ci bigdata                   # 磁碟友善:build+test 全部,全 pass 後 rmi 全部
```

整條 chain 有 12 顆且組件龐大,`ci` 的磁碟峰值仍然可觀——建議單顆迭代用 `dev`,整族驗證再用 `ci`。

## 升級

升組件版本:改 `versions.conf` 的組件鍵(`<組件>_DIR` / `_URL` / `_SHA256` 或 `_SHA512` 三者要同時改),再 bump `SERVICE_VERSION`,然後重 build 整條 chain。

checksum 一律取自上游官方發佈的校驗檔;上游只發 md5 時,以本地下載計算 sha256 並與上游 md5 交叉驗證後寫入,並在 `versions.conf` 的註解說明來源。
