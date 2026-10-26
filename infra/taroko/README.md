# `infra/taroko/` — Taroko 樣板

K8s node + server matrix(18 nodes + 4 cri-docker servers + 1 docker server)。Matrix-based,沒有 `SERVICE_VERSION`／`CHAIN` 概念,沒有 testfile。`UPSTREAM=alpine`。

## 結構

```text
taroko/
├── versions.conf             # UPSTREAM=alpine + NODES + SERVERS_CRI_DOCKER + SERVERS_DOCKER
├── node.Dockerfile           # FROM kindest/node:${KUBERNETES_VERSION} + CNI + helm + bigred user
├── server.Dockerfile         # FROM systemd-ubuntu + cri-dockerd + kubelet/kubeadm/kubectl
├── docker.Dockerfile         # FROM systemd-ubuntu + docker(無 cri-dockerd)
├── root/.bashrc              # 共用
├── home/bigred/.bashrc       # 共用
├── home/bigred/.ssh/         # demo 公鑰 authorized_keys(私鑰不入庫,runtime 由 K8s Secret 注入)
├── etc/default/locale        # 共用 locale
├── etc/crictl.yaml           # cri-docker server 用
└── README.md
```

`*.Dockerfile` 就是正本,沒有渲染步驟——值由 `img.sh` 讀 `versions.conf` 組成 `--build-arg` 餵給 podman;契約鍵寫成光桿 `ARG`(無預設值)。

matrix 三個鍵都是一維空白分隔,`img.sh build taroko` 逐格迭代:

| conf 鍵 | tag 形態 | 帶進去的 `--build-arg` |
|---|---|---|
| `NODES` | `taroko:<單格>` | `KUBERNETES_VERSION=<單格>` |
| `SERVERS_CRI_DOCKER` | `taroko:cri-docker-<單格>` | `KEY_VERSION=<單格>` |
| `SERVERS_DOCKER` | `taroko:docker-<單格>` | 無(`docker.Dockerfile` 沒有對應 ARG) |

其餘契約鍵:`ALPINE_SERVICE_VERSION`(node 的 downloader stage,由 `UPSTREAM=alpine` 衍生)、`CNI_PLUGINS_URL` / `CNI_PLUGINS_SHA256`(node downloader stage)、`HELM_URL` / `HELM_SHA256`(node 第二個 stage)、`CRI_DOCKERD_URL` / `CRI_DOCKERD_SHA256`(server)。

> `node.Dockerfile` 是 multi-stage,而 **`ARG` 不跨 stage**:`CNI_PLUGINS_*` 在 downloader stage 內、`HELM_*` 在第二個 stage 內各自重宣告一次光桿 `ARG`,少宣告一次不會報錯,`${...}` 會靜默展開成空字串。

## Build

```bash
# 磁碟友善:每個 matrix entry build 完即 rmi(峰值僅 1 個 image,~1.4 GB)
bash infra/bin/img.sh ci taroko

# 保留 image 全 matrix(18 nodes + 4 servers + 1 docker = 23 builds,~30 GB 磁碟)
bash infra/bin/img.sh build taroko

# 單格看會拿到哪些值(印 stdout,不 build):
bash infra/bin/img.sh __dump_build_args taroko node KUBERNETES_VERSION=v1.34.0
# 真 build 用 matrix 整批:
bash infra/bin/img.sh build taroko
```

⚠️ 磁碟:18 個 kindest node image 各 ~1.4 GB,全 matrix 約佔 30 GB。可分批 build + `sudo podman image prune` 中間清。

## 新增 K8s 版本

只需在 `versions.conf` 對應的鍵尾端加一格(值含空白,必須維持雙引號):

```conf
NODES="... v1.34.0 v1.35.0"
SERVERS_CRI_DOCKER="v1.31 v1.32 v1.33 v1.34 v1.35"
```

之後 `bash infra/bin/img.sh build taroko` 會自動 build 新版本。
