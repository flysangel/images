# `infra/rdp/` — RDP 桌面樣板

DE × 角色，8 個 service：`lxqt`／`xfce4`（桌面）→ `*-podman`（加 rootless podman）→ `*-k8stools`（加 k8s 工具）→ `*-k8sadm`（加 kubeconfig）。本 family 已遷到 `imgctl`：值在 `catalog.yaml`，煙霧測試在 `tests.yaml`，建置與測試由 `imgctl` 與 GitHub Actions 執行，不用 `img.sh`。

## 結構

```text
rdp/
├── lxqt.Dockerfile             # FROM ${UBUNTU_SSHD_IMAGE}，加 LXQt 與 xrdp
├── xfce4.Dockerfile            # FROM ${UBUNTU_SSHD_IMAGE}，加 XFCE、Firefox 與 xrdp
├── <de>-podman.Dockerfile      # FROM ${RDP_<DE>_IMAGE}，加 ubuntu podman 套件（rootless）
├── <de>-k8stools.Dockerfile    # FROM ${RDP_<DE>_PODMAN_IMAGE}，加 ubuntu k8stools 套件
├── <de>-k8sadm.Dockerfile      # FROM ${RDP_<DE>_K8STOOLS_IMAGE}，注入 kubeconfig template
├── tests.yaml                  # 煙霧測試規格
├── smoke-lxqt.sh               # lxqt 的煙霧測試，由 tests.yaml 的 script 呼叫
├── smoke-xfce4.sh              # xfce4 的煙霧測試，由 tests.yaml 的 script 呼叫
├── smoke-desktop.sh            # 兩個桌面層共用的檢查：ssh 登入、指令在 PATH、xfreerdp 端到端
├── bin/k8sadm-entry.sh         # *-k8sadm 的進入點
├── kube/config                 # *-k8sadm 用的 kubeconfig template
├── home/bigred/.ssh/           # demo 公鑰 authorized_keys（私鑰不入庫，runtime 由 K8s Secret 注入）
├── .imgctl                     # 已遷移標記
└── README.md
```

`<de>` 是 `lxqt` 或 `xfce4`。FROM 的 ARG 名由 `imgctl` 依 family 與 service 名產生，例如 `lxqt-podman` 得 `RDP_LXQT_PODMAN_IMAGE`。

本 family 唯一的契約鍵是 `PROVISION_REF_IN`，由 `catalog.yaml` 的 `aliases` 對到 `PROVISION_REF`。八顆都是丙類，tag 是 `<service>-vX.Y.Z`，下一版由 `imgctl plan` 算出。

## Build 順序

兩條鏈互不相依。桌面層疊在 `ubuntu:sshd` 上，所以 `ubuntu:sshd` 重建時整條鏈跟著重建。

看值表與 tag：

```bash
go run ./cmd/imgctl plan
```

## 煙霧測試

- 每顆都等 xrdp 的 `:3389`。
- podman、k8stools、k8sadm 層用 `tests.yaml` 的 `ssh`、`commands` 與 `files` 驗。
- 桌面層走 script：腳本檢查 ssh 登入與指令，再從 host 用 `xfreerdp` 以 RDP 登入並維持 30 秒。
- 跑桌面層的 host 要有 `xfreerdp` 或 `xfreerdp3`，沒有就直接 `[FAIL]`。host 沒有 X display 時，另要 `xvfb-run`。CI 的安裝步驟在 `.github/workflows/images.yml` 的 test job。

⚠️ 單顆映像約 1.8 GB。
