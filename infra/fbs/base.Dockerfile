# fbs base 樣板:基於 alpine:base + filebrowser get.sh + docker_config.json
# 收尾留 root：filebrowser 的設定檔放在 /root，get.sh 把執行檔裝進 /usr/local/bin，兩者都要 root。
ARG ALPINE_BASE_IMAGE
FROM ${ALPINE_BASE_IMAGE}

# [hadolint] warning: Last USER should not be root (DL3002)
# hadolint ignore=DL3002
USER root
WORKDIR /root

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# /filebrowser 是 docker_config.json 裡 database、log、root 三個路徑的落點，部署時要掛成 volume 才保得住資料。
# get.sh 走上游 master 分支，裝的是建置當下最新的 filebrowser，版本由 catalog.yaml 的 version_from 在建置後探測。
RUN \
    mkdir -p /filebrowser && \
    curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash

# lab／demo 預設憑證，刻意入庫，不是漏洞。正式部署前必須覆寫，不要新增同類明文。
# docker_config.json 含 filebrowser 預設帳號與同名密碼，所以用 0600。
# filebrowser 從 cwd 讀 .filebrowser.json，所以 WORKDIR 是 /root。
COPY --chmod=0600 docker_config.json /root/.filebrowser.json

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["filebrowser"]
