# alpine podman 樣板:fuse-overlayfs + podman.txt 套件清單
ARG ALPINE_SSHD_IMAGE
FROM ${ALPINE_SSHD_IMAGE}
# 釘版穿透:provision 二跳腳本繼承此 ENV(不落回 main)
ARG PROVISION_REF_IN
ENV PROVISION_REF=${PROVISION_REF_IN}

USER root

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# [hadolint] warning: Pin versions in apk add. Instead of `apk add <package>` use `apk add <package>=<version>` (DL3018)
# hadolint ignore=DL3018
RUN \
    apk add --no-cache --update-cache fuse-overlayfs && \
    curl -fsSL https://gitlab.com/flysangel/provision/raw/${PROVISION_REF}/alpine/package/podman/podman.txt | bash

USER bigred
WORKDIR /home/bigred

ENTRYPOINT ["/sbin/tini", "--"]
CMD [ \
    "/bin/bash", \
    "-c", \
    " \
    sudo /usr/sbin/sshd -D -e ;\
    "]
