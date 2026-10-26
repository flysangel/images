# `infra/gmm/` — Guacamole 三件組樣板

3 個 service:`guacd`、`guacamole`(maven multi-stage,custom logo + home.html)、`mariadb`(initdb 注入 schema)。`UPSTREAM=alpine` + `GUACAMOLE_VERSION`。

## 結構

```text
gmm/
├── versions.conf             # SERVICE_VERSION=v1.0.7 + CHAIN + UPSTREAM=alpine + GUACAMOLE_VERSION
├── guacd.Dockerfile          # FROM upstream guacd:${GUACAMOLE_VERSION},加 recordings dir
├── guacamole.Dockerfile      # maven multi-stage(downloader + builder + tomcat runtime)
├── mariadb.Dockerfile        # initdb 取自 upstream guacamole image
├── <service>.testfile
├── ext/                      # custom logo extension assets
├── home/                     # custom home.html
├── images/                   # custom logo PNGs
└── README.md
```

`*.Dockerfile` 就是正本,沒有渲染步驟——值由 `img.sh` 讀 `versions.conf` 組成 `--build-arg` 餵給 podman;契約鍵寫成光桿 `ARG`(無預設值)。

本 family 的契約鍵:`GUACAMOLE_VERSION`(三處消費:guacamole 原始碼 tarball 的 git tag、guacd 的 FROM tag、mariadb initdb stage 的 FROM tag)、`ALPINE_SERVICE_VERSION`(downloader stage 用,由 `UPSTREAM=alpine` 衍生),以及 guacamole 用的全域鍵 `UPSTREAM_DOCKER`。

> `guacamole.Dockerfile` 是全 repo 唯一的三段 multi-stage,`GUACAMOLE_VERSION` 在三個 stage 內文各重宣告一次光桿 `ARG`——**`ARG` 不跨 stage**,少宣告一次會靜默展開成空字串。
>
> builder 與 runtime 兩個 stage 的 `maven`／`tomcat` 走 `${UPSTREAM_DOCKER}`(Docker Hub),不經自家 registry,`sync/repository/` 也沒有這兩顆的同步規則。

## Build 順序

1. `guacd` 與 `guacamole` 互相獨立(同層平行,目前實作循序)
2. `mariadb` 的 initdb.sql 取自 sync 鏡進來的上游 guacamole 映像,不依賴本 repo 的 `guacamole`;三顆彼此無 FROM 依賴

```bash
bash infra/bin/img.sh build gmm                  # 依 chain 全 build
bash infra/bin/img.sh build gmm guacd            # 單一
bash infra/bin/img.sh __dump_build_args gmm guacamole    # 印 --build-arg 值表(debug)
bash infra/bin/img.sh test gmm guacamole         # smoke test
bash infra/bin/img.sh ci gmm                     # build+test 全部後 rmi(磁碟友善)
```

⚠️ guacamole 是 maven multi-stage(含 Firefox 安裝、Java/JS 單元測試),首次 build 約 10-20 分鐘;後續因 layer cache 較快。
