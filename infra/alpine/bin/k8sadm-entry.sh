#!/bin/bash
# 與另一個 family 的 k8sadm-entry.sh 及兩份 kube/config 內容重複，屬刻意的家族自足，不抽共用。
# alpine k8sadm 進入點:從 pod serviceaccount 渲染 kubeconfig,再前景起 sshd 保活
# 不設 set -e:逐條容忍暫時失敗(如 kubectl auth whoami 於 API 未就緒時),與原 CMD 行為一致
# 渲染只在 pod 內有效：pod 外 kubectl auth whoami 會失敗、kubeconfig 無效，但 sshd 照起；testfile 用 podman run 驗不到這段。

# kubeconfig(從 pod serviceaccount 渲染)
export KUBE_EDITOR='nano'
export CA=$(base64 < /run/secrets/kubernetes.io/serviceaccount/ca.crt | tr -d '\n')
export TOKEN=$(cat /run/secrets/kubernetes.io/serviceaccount/token)
export NAMESPACE=$(cat /run/secrets/kubernetes.io/serviceaccount/namespace)
export KUBEUSER=$(kubectl auth whoami -o jsonpath='{.status.userInfo.username}')
mkdir ~/.kube 2>/dev/null

envsubst < ~/.kube/config.tmp > ~/.kube/config

# sshd(exec 前景保活,直接承接 tini 信號)
exec sudo /usr/sbin/sshd -D -e
