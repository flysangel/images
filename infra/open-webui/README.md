# `infra/open-webui/` — Open WebUI dbadm 樣板

單 service:`dbadm`(open-webui 帳號管理 helper),`UPSTREAM=alpine`。

## 結構

```text
open-webui/
├── versions.conf             # SERVICE_VERSION=v1.0.1 + CHAIN=dbadm + UPSTREAM=alpine
├── dbadm.Dockerfile          # FROM library/alpine:${ALPINE_BASE}
├── dbadm.testfile
├── adduser.sh                # COPY 進 image /bin/
├── deluser.sh
├── lsuser.sh
├── resetpasswd.sh
└── README.md
```

`dbadm.Dockerfile` 就是正本,沒有渲染步驟——唯一的契約鍵 `ALPINE_BASE` 寫成光桿 `ARG`,值由 `img.sh` 依 `UPSTREAM=alpine` 從 `infra/alpine/versions.conf` 的 `BASE` 衍生(注意:本 image 直接 FROM `library/alpine`,不是 FROM `alpine:base`,因此用 `ALPINE_BASE` 而非 `ALPINE_SERVICE_VERSION`)。

## Build

```bash
bash infra/bin/img.sh build open-webui          # build dbadm
bash infra/bin/img.sh __dump_build_args open-webui dbadm   # 印 --build-arg 值表(debug)
bash infra/bin/img.sh test open-webui dbadm     # smoke test
bash infra/bin/img.sh ci open-webui             # build + test + rmi(磁碟友善)
```
