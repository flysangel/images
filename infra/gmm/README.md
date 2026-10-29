# `infra/gmm/` — Guacamole 三件組樣板

3 個 service：`guacd`、`guacamole`（maven multi-stage，custom logo 與 home.html）、`mariadb`（initdb 注入 schema）。本 family 已遷到 `imgctl`：值在 `catalog.yaml`，煙霧測試在 `tests.yaml`，建置與測試由 `imgctl` 與 GitHub Actions 執行，不用 `img.sh`。

## 結構

```text
gmm/
├── guacd.Dockerfile          # FROM ${GUACAMOLE_GUACD_IMAGE}，加 recordings 目錄
├── guacamole.Dockerfile      # downloader（alpine:base）+ builder（maven）+ runtime（tomcat）
├── mariadb.Dockerfile        # initdb 取自上游 guacamole 映像，最終層是上游 mariadb
├── tests.yaml                # 煙霧測試規格，三顆都走 script
├── smoke-<service>.sh        # 各 service 的煙霧測試腳本，由 tests.yaml 的 script 呼叫
├── ext/                      # custom logo extension assets
├── home/                     # custom home.html
├── images/                   # custom logo PNGs
├── .imgctl                   # 已遷移標記
└── README.md
```

外部映像（guacd、guacamole、mariadb、maven、tomcat）都是同步進自家 registry 的副本，列在 `catalog.yaml` 的 `upstream` 並釘 digest。maven 與 tomcat 的同步規則在 `sync/repository/library.yaml`，只鏡用到的 tag。

本 family 唯一的契約鍵是 `GUACAMOLE_VERSION`，只有 `guacamole.Dockerfile` 用：downloader 抓 guacamole-client 原始碼 tarball 的 git tag。升 Guacamole 時，`catalog.yaml` 的 `GUACAMOLE_VERSION`、`guacd` 與 `guacamole` 的 `version`、`GUACAMOLE_GUACD` 與 `GUACAMOLE_GUACAMOLE` 的 ref 與 digest 要一起改。

> `guacamole.Dockerfile` 是三段 multi-stage，`GUACAMOLE_VERSION` 在三個 stage 內文各重宣告一次光桿 `ARG`。**`ARG` 不跨 stage**，少宣告一次會靜默展開成空字串，`imgctl lint` 擋這條。

## Build 順序

三顆彼此沒有 FROM 依賴。`guacamole` 的 downloader 疊 `alpine:base`，所以 `alpine:base` 重建時 `guacamole` 跟著重建。`mariadb` 的 initdb.sql 取自上游 guacamole 映像，不依賴本 repo 的 `guacamole`。

看值表與 tag：

```bash
go run ./cmd/imgctl plan
```

⚠️ guacamole 是 maven multi-stage（含 Firefox 安裝、Java／JS 單元測試），首次 build 約 10-20 分鐘；後續因 layer cache 較快。
