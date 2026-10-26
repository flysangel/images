# taroko docker server 樣板(基於 jrei/systemd-ubuntu + docker,無 cri-docker / kubelet)
# 無專屬 KEY=VAL 覆寫,僅通用 REGISTRY_PREFIX 與 PROVISION_REF(皆為光桿 ARG,值由 img.sh 以 --build-arg 注入)

ARG REGISTRY_PREFIX
FROM ${REGISTRY_PREFIX}/jrei/systemd-ubuntu:24.04
# 釘版穿透:provision 二跳腳本繼承此 ENV(不落回 main)
ARG PROVISION_REF_IN
ENV PROVISION_REF=${PROVISION_REF_IN}

# 切 pipefail:下方多處 curl ... | bash,無此 flag 時管線前段失敗會被 bash 結束碼吞掉
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# [hadolint] warning: Last USER should not be root (DL3002)
# hadolint ignore=DL3002
USER root

# [hadolint] warning: Pin versions in apt get install. Instead of `apt-get install <package>` use `apt-get install <package>=<version>` (DL3008)
# hadolint ignore=DL3008
RUN \
    apt-get update --fix-missing && \
    apt-get install -y --no-install-recommends curl && \
    apt-get clean -y && \
    apt-get autoclean -y && \
    rm -rf /var/lib/apt/lists/* && \
    curl -fsSL https://gitlab.com/flysangel/provision/raw/${PROVISION_REF}/ubuntu/system/base/base.txt | bash && \
    curl -fsSL https://gitlab.com/flysangel/provision/raw/${PROVISION_REF}/ubuntu/system/ntp/ntp.txt | bash && \
    curl -fsSL https://gitlab.com/flysangel/provision/raw/${PROVISION_REF}/ubuntu/system/locale/locale.txt | bash

# [hadolint] warning: Pin versions in apt get install. Instead of `apt-get install <package>` use `apt-get install <package>=<version>` (DL3008)
# hadolint ignore=DL3008
RUN \
    apt-get update --fix-missing && \
    apt-get install -y --no-install-recommends openssh-server && \
    apt-get clean -y && \
    apt-get autoclean -y && \
    rm -rf /var/lib/apt/lists/* && \
    curl -fsSL https://gitlab.com/flysangel/provision/raw/${PROVISION_REF}/ubuntu/system/bigred/bigred.txt | bash && \
    curl -fsSL https://gitlab.com/flysangel/provision/raw/${PROVISION_REF}/ubuntu/system/sshenv/sshenv.txt | bash && \
    curl -fsSL https://gitlab.com/flysangel/provision/raw/${PROVISION_REF}/ubuntu/system/sudopw/sudopw.txt | bash && \
    systemctl enable ssh

RUN \
    curl -fsSL https://gitlab.com/flysangel/provision/raw/${PROVISION_REF}/ubuntu/package/docker/docker.txt | bash && \
    systemctl enable docker

ENV LANG=en_US.UTF-8

# 私鑰不進 image(Phase 3a):runtime 由 K8s Secret 注入;context 僅 authorized_keys,權限由 COPY --chmod 定
# demo 公鑰刻意入庫供 image-time COPY，對應私鑰已移除，runtime 由 K8s Secret 注入。
COPY --chmod=0700 --chown=bigred:bigred home/bigred/.ssh /home/bigred/.ssh
# 不 COPY home/bigred/.bashrc：那份 .bashrc 會 source kubectl completion，本映像沒有 kubectl。
