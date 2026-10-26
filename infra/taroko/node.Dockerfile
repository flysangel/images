# taroko node 樣板(基於 kindest/node + 由 alpine:base downloader 帶 CNI plugins)
# 由 img.sh build taroko 走獨立分支,每個 nodes[].kubernetes 各 build 一次
# 收尾留 root：執行期以 root 跑 kubeadm 與 CNI 佈建。

ARG REGISTRY_PREFIX
ARG ALPINE_SERVICE_VERSION
ARG DOWNLOADER_IMAGE=${REGISTRY_PREFIX}/alpine:base-${ALPINE_SERVICE_VERSION}
ARG KUBERNETES_VERSION

# ---
# [hadolint] warning: Always tag the version of an image explicitly (DL3006)
# hadolint ignore=DL3006
FROM ${DOWNLOADER_IMAGE} AS downloader

# [hadolint] warning: Last USER should not be root (DL3002)
# hadolint ignore=DL3002
USER root

ARG CNI_PLUGINS_URL
ARG CNI_PLUGINS_SHA256

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# cni-plugins 釘版 CNI_PLUGINS_URL + sha256 校驗(取代 build 期 releases/latest 浮動查詢,確保映像可重現/airgap)
RUN \
    curl -fsSL "${CNI_PLUGINS_URL}" -o /tmp/cni-plugins.tgz && \
    echo "${CNI_PLUGINS_SHA256}  /tmp/cni-plugins.tgz" | sha256sum -c -

FROM ${REGISTRY_PREFIX}/kindest/node:${KUBERNETES_VERSION}

USER root

# node 不走 provision 的二跳腳本，使用者、時區、sshd 設定都在本檔做；AUID 要與 provision bigred.txt 的 AUID 一致，兩處各寫一份。
# PASSWORD 是 lab／demo 預設憑證，刻意入庫，不是漏洞。正式部署前必須覆寫，不要新增同類明文。
ARG USERNAME=bigred
ARG PASSWORD=bigred
ARG AUID=1001
ARG HELM_URL
ARG HELM_SHA256

# [hadolint] warning: Pin versions in apt get install. Instead of `apt-get install <package>` use `apt-get install <package>=<version>` (DL3008)
# hadolint ignore=DL3008
RUN \
    apt-get update --fix-missing && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    sudo bash \
    ssh sshpass \
    jq yq nano vim tree curl acl git \
    p7zip-full \
    net-tools iputils-ping dnsutils \
    bash-completion \
    tini && \
    apt-get clean -y && \
    apt-get autoclean -y && \
    rm -rf /var/lib/apt/lists/*

# %sudo 群組 sudo 免密碼;已含 NOPASSWD 則跳過(冪等)
RUN \
    grep -q '%sudo.*NOPASSWD:ALL' /etc/sudoers || sed -i '/^%sudo/s/ALL$/NOPASSWD:ALL/' /etc/sudoers

COPY --from=downloader /tmp/cni-plugins.tgz /tmp/cni-plugins.tgz
RUN \
    tar xf /tmp/cni-plugins.tgz -C /opt/cni/bin && \
    rm -rf /tmp/cni-plugins.tgz

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# helm 釘版 HELM_URL + sha256 校驗(get.helm.sh 官方源;取代 build 期 releases/latest 浮動查詢)
RUN \
    curl -fsSL "${HELM_URL}" -o helm.tar.gz && \
    echo "${HELM_SHA256}  helm.tar.gz" | sha256sum -c - && \
    tar xf helm.tar.gz && \
    install -o root -g root -m 0755 linux-amd64/helm /usr/local/bin/helm && \
    rm -rf helm* linux-amd64

# ssh-keygen -A 在建置期產 host key，同一個 tag 起的所有容器共用同一把。
RUN \
    # ssh_config client use
    grep -x 'StrictHostKeyChecking no' /etc/ssh/ssh_config || echo '    StrictHostKeyChecking no' | tee -a /etc/ssh/ssh_config && \
    # sshd_config server use
    grep -x 'X11UseLocalhost yes' /etc/ssh/sshd_config || echo 'X11UseLocalhost yes' | tee -a /etc/ssh/sshd_config && \
    grep -x 'PermitRootLogin no' /etc/ssh/sshd_config || echo 'PermitRootLogin no' | tee -a /etc/ssh/sshd_config && \
    grep -x 'PermitUserEnvironment yes' /etc/ssh/sshd_config || echo 'PermitUserEnvironment yes' | tee -a /etc/ssh/sshd_config && \
    grep -x 'HostKeyAlgorithms +ssh-rsa' /etc/ssh/sshd_config || echo 'HostKeyAlgorithms +ssh-rsa' | tee -a /etc/ssh/sshd_config && \
    grep -x 'PubkeyAcceptedKeyTypes +ssh-rsa' /etc/ssh/sshd_config || echo 'PubkeyAcceptedKeyTypes +ssh-rsa' | tee -a /etc/ssh/sshd_config && \
    ssh-keygen -t rsa -A

RUN \
    # timezone
    rm -rf /etc/localtime && \
    cp /usr/share/zoneinfo/Asia/Taipei /etc/localtime

RUN \
    useradd -s /bin/bash -m -l -G sudo -u ${AUID} ${USERNAME} && \
    echo ${USERNAME}:${PASSWORD} | chpasswd && \
    chown -R ${USERNAME}:${USERNAME} /home/${USERNAME} && \
    chmod 700 /home/${USERNAME}

# 私鑰不進 image(Phase 3a):runtime 由 K8s Secret 注入;context 僅 authorized_keys,權限由 COPY --chmod 定
# demo 公鑰刻意入庫供 image-time COPY，對應私鑰已移除，runtime 由 K8s Secret 注入。
COPY --chmod=0700 --chown=${USERNAME}:${USERNAME} home/${USERNAME}/.ssh /home/${USERNAME}/.ssh

COPY --chmod=0644 --chown=${USERNAME}:${USERNAME} home/${USERNAME}/.bashrc /home/${USERNAME}/.bashrc
COPY --chmod=0644 etc/default/locale /etc/default/locale
COPY --chmod=0644 root/.bashrc /root/.bashrc

ENV LANG=en_US.UTF-8

# [hadolint] warning: Last USER should not be root (DL3002)
# hadolint ignore=DL3002
USER root
WORKDIR /root
