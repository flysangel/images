# taroko cri-docker server 樣板(基於 jrei/systemd-ubuntu + cri-dockerd + kubelet/kubeadm/kubectl)
# KEY_VERSION 由 img.sh build taroko 從 versions.conf 的 SERVERS_CRI_DOCKER 逐格帶入（--build-arg）

ARG REGISTRY_PREFIX
FROM ${REGISTRY_PREFIX}/jrei/systemd-ubuntu:24.04
# 釘版穿透:provision 二跳腳本繼承此 ENV(不落回 main)
ARG PROVISION_REF_IN
ENV PROVISION_REF=${PROVISION_REF_IN}

ARG KEY_VERSION
ARG CRI_DOCKERD_URL
ARG CRI_DOCKERD_SHA256

# [hadolint] warning: Last USER should not be root (DL3002)
# hadolint ignore=DL3002
USER root

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

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

COPY --chmod=644 --chown=root:root etc/crictl.yaml /etc/crictl.yaml

# cri-dockerd 釘版 CRI_DOCKERD_URL + sha256 校驗(取代 build 期 releases/latest 浮動查詢,確保映像可重現/airgap)
RUN \
    curl -fsSL "${CRI_DOCKERD_URL}" -o cri-dockerd.deb && \
    echo "${CRI_DOCKERD_SHA256}  cri-dockerd.deb" | sha256sum -c - && \
    dpkg -i cri-dockerd.deb && \
    rm -rf cri-dockerd.deb && \
    systemctl enable cri-docker

# [hadolint] warning: Pin versions in apt get install. Instead of `apt-get install <package>` use `apt-get install <package>=<version>` (DL3008)
# hadolint ignore=DL3008
RUN \
    apt-get update && \
    apt-get install -y --no-install-recommends apt-transport-https ca-certificates curl gpg && \
    curl -fsSL https://pkgs.k8s.io/core:/stable:/${KEY_VERSION}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${KEY_VERSION}/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends kubelet kubeadm kubectl && \
    apt-get clean -y && \
    apt-get autoclean -y && \
    rm -rf /var/lib/apt/lists/* && \
    apt-mark hold kubelet kubeadm kubectl && \
    systemctl enable kubelet

# 私鑰不進 image(Phase 3a):runtime 由 K8s Secret 注入;context 僅 authorized_keys,權限由 COPY --chmod 定
# demo 公鑰刻意入庫供 image-time COPY，對應私鑰已移除，runtime 由 K8s Secret 注入。
COPY --chmod=0700 --chown=bigred:bigred home/bigred/.ssh /home/bigred/.ssh

COPY --chmod=0644 --chown=bigred:bigred home/bigred/.bashrc /home/bigred/.bashrc

ENV LANG=en_US.UTF-8
