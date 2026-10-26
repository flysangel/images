# alpine base 樣板:apk 裝 sudo/bash/curl,跑 provision 的 base + ntp 設定
# BASE 由 infra/alpine/versions.conf 經 img.sh 以 --build-arg 注入（光桿 ARG＝契約值）

ARG REGISTRY_PREFIX
ARG BASE
FROM ${REGISTRY_PREFIX}/library/alpine:${BASE}
# 釘版穿透:provision 二跳腳本繼承此 ENV(不落回 main)
ARG PROVISION_REF_IN
ENV PROVISION_REF=${PROVISION_REF_IN}

USER root

# 先用預設 /bin/sh 安裝 bash + curl（後面 SHELL 才能切 bash 與 pipefail）
# [hadolint] warning: Pin versions in apk add. Instead of `apk add <package>` use `apk add <package>=<version>` (DL3018)
# hadolint ignore=DL3018
RUN apk add --no-cache --update-cache sudo bash curl

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN \
    curl -fsSL https://gitlab.com/flysangel/provision/raw/${PROVISION_REF}/alpine/system/base/base.txt | bash && \
    curl -fsSL https://gitlab.com/flysangel/provision/raw/${PROVISION_REF}/alpine/system/ntp/ntp.txt | bash

ENV LANG=en_US.UTF-8

# [hadolint] warning: Last USER should not be root (DL3002)
# hadolint ignore=DL3002
USER root
WORKDIR /root

ENTRYPOINT ["/sbin/tini", "--"]
CMD [ \
    "/bin/bash", \
    "-c", \
    " \
    sleep infinity;\
    "]
