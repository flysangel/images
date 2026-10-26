# rdp xfce4-podman 樣板:基於 rdp:xfce4 + ubuntu podman 套件(rootless container-in-container)
ARG REGISTRY_PREFIX
ARG SERVICE_VERSION
FROM ${REGISTRY_PREFIX}/rdp:xfce4-${SERVICE_VERSION}

# 釘版穿透:provision 二跳腳本繼承此 ENV(不落回 main)
ARG PROVISION_REF_IN
ENV PROVISION_REF=${PROVISION_REF_IN}

USER root

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN \
    curl -fsSL https://gitlab.com/flysangel/provision/raw/${PROVISION_REF}/ubuntu/package/podman/podman.txt | bash

USER bigred
WORKDIR /home/bigred

# ENTRYPOINT/CMD 不重宣告 → 繼承 rdp:xfce4(tini + xrdp/sesman/sshd)
