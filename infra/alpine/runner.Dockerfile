# alpine runner 樣板：clone-and-run cronjob 執行器；FROM alpine:base（已含 git/jq/bind-tools/curl）+ go-task
# 唯一缺的工具是 go-task（provision taskfile 套件補）；base 收尾 USER root（bigred 自 sshd 層起才有），故沿用 root
ARG ALPINE_BASE_IMAGE
FROM ${ALPINE_BASE_IMAGE}
# 釘版穿透：provision 二跳腳本繼承此 ENV
ARG PROVISION_REF_IN
ENV PROVISION_REF=${PROVISION_REF_IN}

USER root

# 切 bash 開 pipefail：讓下面 curl | bash 下載失敗時中斷建置（否則管線只看 bash 退出碼，會吞掉 curl 的錯）
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN \
    curl -fsSL https://gitlab.com/flysangel/provision/raw/${PROVISION_REF}/alpine/package/taskfile/taskfile.txt | bash
