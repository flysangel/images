# alpine k8stools 樣板:基於 alpine:podman + minio/mc + k8stools 套件清單
# 疊在 alpine:podman 上不是 sshd：k8stools.txt 裝的 kind 要有容器引擎才能起叢集。

ARG REGISTRY_PREFIX
ARG SERVICE_VERSION
# [hadolint] warning: Always tag the version of an image explicitly (DL3006)
# hadolint ignore=DL3006
FROM ${REGISTRY_PREFIX}/minio/mc AS mc

FROM ${REGISTRY_PREFIX}/alpine:podman-${SERVICE_VERSION}
# 釘版穿透:provision 二跳腳本繼承此 ENV(不落回 main)
ARG PROVISION_REF_IN
ENV PROVISION_REF=${PROVISION_REF_IN}

USER root

COPY --from=mc /usr/bin/mc /tmp/mc

RUN \
    install -o root -g root -m 0755 /tmp/mc /usr/local/bin/mc && \
    rm -rf /tmp/mc*

# 開 pipefail:下一個 RUN 走 curl | bash,curl 失敗才會讓建置失敗(否則只看 bash 退出碼)
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN \
    curl -fsSL https://gitlab.com/flysangel/provision/raw/${PROVISION_REF}/alpine/package/k8stools/k8stools.txt | bash

USER bigred
WORKDIR /home/bigred

ENTRYPOINT ["/sbin/tini", "--"]
CMD [ \
    "/bin/bash", \
    "-c", \
    " \
    sudo /usr/sbin/sshd -D ;\
    "]
