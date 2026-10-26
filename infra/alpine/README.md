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

alpine 已遷移到 `imgctl`。`infra/bin/img.sh` 與 `task *:image` 不能建它（FROM 是光桿 `*_IMAGE`，沒有 `imgctl` 供值）。值在 [`../../catalog.yaml`](../../catalog.yaml)，煙霧測試在 `tests.yaml`，建置與測試由 `imgctl` 與 GitHub Actions 執行：

```bash
# 印 plan：哪些 service 要重建
go run ./cmd/imgctl plan

# 檢查 Dockerfile 與 catalog 一致
go run ./cmd/imgctl lint
```

## 升級

升 Alpine base 或 service version 改 `catalog.yaml`，不改 `versions.conf`（已凍結，只供其他 family 取 alpine 的上游值）。

> `sync/kustomization.yaml` 的 `newTag`（同步 CronJob 用的 `alpine:podman-<版本>`）是第二個落點。升版時兩處要一起改，目前無人執法（見 [`../../docs/PROGRESS.md`](../../docs/PROGRESS.md) 待辦）。

push 到 `main` 後，CI 會用新版重建。
