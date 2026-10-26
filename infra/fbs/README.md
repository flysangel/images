# `infra/fbs/` — Filebrowser 樣板

單 service:`base`(filebrowser web 介面),`UPSTREAM=alpine`。

## 結構

```text
fbs/
├── versions.conf             # SERVICE_VERSION=v1.0.3 + CHAIN=base + UPSTREAM=alpine
├── base.Dockerfile           # FROM alpine:base-${ALPINE_SERVICE_VERSION}
├── base.testfile
├── docker_config.json        # filebrowser 預設設定;baked into image as /root/.filebrowser.json
└── README.md
```

`base.Dockerfile` 就是正本,沒有渲染步驟——唯一的契約鍵 `ALPINE_SERVICE_VERSION` 寫成光桿 `ARG`,值由 `img.sh` 依 `UPSTREAM=alpine` 從 `infra/alpine/versions.conf` 的 `SERVICE_VERSION` 衍生,以 `--build-arg` 傳入。

⚠️ `docker_config.json` 內預設 `admin/admin` 帳密,僅 demo 用;runtime 應透過 env 或 volume 覆寫。

## Build

```bash
bash infra/bin/img.sh build fbs           # build base
bash infra/bin/img.sh __dump_build_args fbs base   # 印 --build-arg 值表(debug)
bash infra/bin/img.sh test fbs base       # smoke test
bash infra/bin/img.sh ci fbs              # build + test + rmi(磁碟友善)
```
