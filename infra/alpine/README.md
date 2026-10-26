# `infra/alpine/` — Alpine 樣板

Alpine family,8 個 service 依繼承鏈 build。

## 結構

```text
alpine/
├── versions.conf             # BASE=3.21.3 + SERVICE_VERSION=v1.0.3 + CHAIN
├── base.Dockerfile           # FROM library/alpine
├── sshd.Dockerfile           # FROM alpine:base
├── podman.Dockerfile         # FROM alpine:sshd
├── qemu.Dockerfile           # FROM alpine:sshd
├── s3cli.Dockerfile          # FROM alpine:sshd + minio/mc + seaweedfs
├── k8stools.Dockerfile       # FROM alpine:podman + minio/mc
├── k8sadm.Dockerfile         # FROM alpine:k8stools(注入 kubeconfig template)
├── runner.Dockerfile         # FROM alpine:base
├── <service>.testfile        # 對應 smoke test
├── bin/k8sadm-entry.sh       # k8sadm 的 entrypoint:渲染 kubeconfig 後 exec sshd
├── kube/config               # k8sadm 用的 kubeconfig template
└── README.md
```

`*.Dockerfile` 就是正本,沒有渲染步驟——值由 `img.sh` 讀 `versions.conf` 組成 `--build-arg` 餵給 podman。
契約鍵寫成光桿 `ARG`(無預設值),`versions.conf` 沒有對應鍵即 fail-fast;帶預設值的 `ARG X=y` 是 Dockerfile 自有、不受值表管轄。

本 family 的契約鍵:`BASE`(base.Dockerfile 用)、`SERVICE_VERSION`(其餘 service 用),另有 `SEAWEEDFS_URL` / `SEAWEEDFS_SHA256`(s3cli 用,官方 release 源 + sha256 校驗)。全域鍵 `REGISTRY_PREFIX` 與 `PROVISION_REF_IN` 由 `img.sh` 供給。

## Build

```bash
# build 整 family,依 chain 順序
bash infra/bin/img.sh build alpine

# build 單一 service
bash infra/bin/img.sh build alpine sshd

# 印該顆會拿到的 --build-arg 值表(不 build,debug 用;取代已退役的 render 子命令)
bash infra/bin/img.sh __dump_build_args alpine sshd

# 跑 smoke test(image 必須先 build)
bash infra/bin/img.sh test alpine sshd

# 磁碟友善 CI:依 chain build + test 全部,全成功後 rmi 全部
bash infra/bin/img.sh ci alpine
```

## 升級

升 Alpine base 或 service version 只需改 `versions.conf`,例如:

```conf
BASE=3.22.0             # 升級到 3.22
SERVICE_VERSION=v1.0.4  # 新 service 版本
```

> `SERVICE_VERSION` 另有第二個落點:`sync/kustomization.yaml` 的 `newTag`(同步 CronJob 用的 `alpine:podman-<版本>`)。升版時兩處要一起改,目前無人執法(見 [`../../docs/PROGRESS.md`](../../docs/PROGRESS.md) 待辦)。

之後 `bash infra/bin/img.sh build alpine` 會用新版重 build。
