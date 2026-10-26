# rdp lxqt-k8stools 樣板:基於 rdp:lxqt-podman + ubuntu k8stools 套件清單(kubectl/helm/kind/kustomize/...)
ARG REGISTRY_PREFIX
ARG SERVICE_VERSION
FROM ${REGISTRY_PREFIX}/rdp:lxqt-podman-${SERVICE_VERSION}

# 釘版穿透:provision 二跳腳本繼承此 ENV(不落回 main)
ARG PROVISION_REF_IN
ENV PROVISION_REF=${PROVISION_REF_IN}

USER root

# pipefail:curl 失敗即中止建置,不被管線末端 bash 的結果掩蓋
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN \
    curl -fsSL https://gitlab.com/flysangel/provision/raw/${PROVISION_REF}/ubuntu/package/k8stools/k8stools.txt | bash

USER bigred
WORKDIR /home/bigred

# ENTRYPOINT/CMD 不重宣告 → 繼承 rdp:lxqt(tini + xrdp/sesman/sshd)
