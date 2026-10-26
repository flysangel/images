#!/bin/bash
# 與另一個 family 的 k8sadm-entry.sh 及兩份 kube/config 內容重複，屬刻意的家族自足，不抽共用。
# rdp k8sadm 進入點(lxqt/xfce4 共用):渲染 kubeconfig → 起 xrdp 桌面 → 前景起 sshd 保活
# 不設 set -e:逐條容忍暫時失敗(如 kubectl auth whoami 於 API 未就緒時),與原 CMD 行為一致
# 渲染只在 pod 內有效：pod 外 kubectl auth whoami 會失敗、kubeconfig 無效，但 sshd 照起；testfile 用 podman run 驗不到這段。

# kubeconfig(從 pod serviceaccount 渲染)
export KUBE_EDITOR='nano'
export CA=$(cat /run/secrets/kubernetes.io/serviceaccount/ca.crt | base64 | tr -d '\n')
export TOKEN=$(cat /run/secrets/kubernetes.io/serviceaccount/token)
export NAMESPACE=$(cat /run/secrets/kubernetes.io/serviceaccount/namespace)
export KUBEUSER=$(kubectl auth whoami -o jsonpath='{.status.userInfo.username}')
mkdir ~/.kube 2>/dev/null

envsubst < ~/.kube/config.tmp > ~/.kube/config

# xrdp 桌面（與 xfce4、lxqt Dockerfile 的 CMD 是同一段啟動序，改一邊要同步另一邊）
sudo rm -rf /run/dbus/pid /var/run/xrdp/xrdp-sesman.pid /var/run/xrdp/xrdp.pid
sudo /usr/bin/dbus-daemon --system --fork
sudo /usr/sbin/xrdp-sesman
sudo /usr/sbin/xrdp

# sshd(exec 前景保活;install 先建 /run/sshd,沿用原 && 短路語意)
sudo install -m 0755 -d /run/sshd && exec sudo /usr/sbin/sshd -D -e
