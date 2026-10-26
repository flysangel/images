# `infra/rdp/` — RDP 桌面樣板

DE × 角色,8 個 service:`lxqt`/`xfce4`(桌面)→ `*-podman`(+rootless podman)→ `*-k8stools`(+k8s 工具)→ `*-k8sadm`(+kubeconfig),`UPSTREAM=ubuntu`。桌面層基於 ubuntu:sshd 可平行。

## 結構

```text
rdp/
├── versions.conf             # SERVICE_VERSION=v1.0.2 + CHAIN(八顆) + UPSTREAM=ubuntu
├── lxqt.Dockerfile           # FROM ubuntu:sshd-${UBUNTU_SERVICE_VERSION} + LXQt + xrdp
├── xfce4.Dockerfile          # FROM ubuntu:sshd-${UBUNTU_SERVICE_VERSION} + XFCE + Firefox + xrdp
├── lxqt-podman.Dockerfile      # FROM rdp:lxqt  + ubuntu podman 套件(rootless)
├── xfce4-podman.Dockerfile     # FROM rdp:xfce4 + ubuntu podman 套件(rootless)
├── lxqt-k8stools.Dockerfile       # FROM rdp:lxqt-podman  + ubuntu k8stools 套件
├── xfce4-k8stools.Dockerfile      # FROM rdp:xfce4-podman + ubuntu k8stools 套件
├── lxqt-k8sadm.Dockerfile         # FROM rdp:lxqt-k8stools  + 注入 kubeconfig template
├── xfce4-k8sadm.Dockerfile        # FROM rdp:xfce4-k8stools + 注入 kubeconfig template
├── <service>.testfile        # 對應 smoke test
├── kube/config               # *-k8sadm 用的 kubeconfig template
├── home/bigred/.ssh/         # demo 公鑰 authorized_keys(私鑰不入庫,runtime 由 K8s Secret 注入)
└── README.md
```

`*.Dockerfile` 就是正本,沒有渲染步驟——值由 `img.sh` 讀 `versions.conf` 組成 `--build-arg` 餵給 podman;契約鍵寫成光桿 `ARG`(無預設值)。

本 family 的契約鍵:`UBUNTU_SERVICE_VERSION`(桌面層用,由 `UPSTREAM=ubuntu` 從 `infra/ubuntu/versions.conf` 衍生)、`SERVICE_VERSION`(podman／k8stools／k8sadm 層用,即 rdp 家族版,FROM 同家族上一層)。

`CHAIN` 是一維空白分隔的建置序;原本 YAML 時代的四層分組邊界已取消,同層可平行的資訊改由 `versions.conf` 的註解表達。

## Build

```bash
bash infra/bin/img.sh build rdp                 # 整 family(lxqt + xfce4)
bash infra/bin/img.sh build rdp xfce4           # 單一
bash infra/bin/img.sh __dump_build_args rdp lxqt   # 印 --build-arg 值表(debug)
bash infra/bin/img.sh test rdp lxqt             # smoke test(需 host 有 xfreerdp)
bash infra/bin/img.sh ci rdp                    # build+test 全部後 rmi(磁碟友善;單 image ~1.8 GB)
```

⚠️ smoke test 需 host 安裝 `xfreerdp`(見 lxqt.testfile / xfce4.testfile 註解)。
