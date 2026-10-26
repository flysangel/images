# `infra/ubuntu/` — Ubuntu 樣板

Ubuntu family,3 個 service:base → sshd → knife。

## 結構

```text
ubuntu/
├── versions.conf             # BASE=24.04 + SERVICE_VERSION=v1.0.4 + CHAIN
├── base.Dockerfile           # FROM library/ubuntu
├── sshd.Dockerfile           # FROM ubuntu:base
├── knife.Dockerfile          # FROM ubuntu:sshd + net/disk diagnostics + kubectl
├── <service>.testfile        # smoke test
└── README.md
```

`*.Dockerfile` 就是正本,沒有渲染步驟——值由 `img.sh` 讀 `versions.conf` 組成 `--build-arg` 餵給 podman;契約鍵寫成光桿 `ARG`(無預設值)。

本 family 的契約鍵:`BASE`(base 用)、`SERVICE_VERSION`(其餘用)。`SERVICE_VERSION` 同時被 bigdata 與 rdp 以 `UBUNTU_SERVICE_VERSION` 取用,鍵名不可改。

## Build

```bash
bash infra/bin/img.sh build ubuntu                # 整 family
bash infra/bin/img.sh build ubuntu knife          # 單一
bash infra/bin/img.sh __dump_build_args ubuntu sshd   # 印 --build-arg 值表(debug)
bash infra/bin/img.sh test ubuntu base            # smoke test
bash infra/bin/img.sh ci ubuntu                   # 磁碟友善:build+test 全部,全 pass 後 rmi 全部
```

## 升級

改 `versions.conf`:`BASE=26.04` 或 `SERVICE_VERSION=v1.0.5`,再 `bash infra/bin/img.sh build ubuntu`。

> `BASE` 在舊的 `versions.yaml` 寫成 `base: "24.04"`,引號是為了擋 YAML 把它解成浮點數;`versions.conf` 會被 `source`,不含空白的值一律不加引號。
