# rdp lxqt 樣板:基於 ubuntu:sshd + xrdp + LXQt
ARG REGISTRY_PREFIX
ARG UBUNTU_SERVICE_VERSION
FROM ${REGISTRY_PREFIX}/ubuntu:sshd-${UBUNTU_SERVICE_VERSION}
# 釘版穿透:provision 二跳腳本繼承此 ENV(不落回 main)
ARG PROVISION_REF_IN
ENV PROVISION_REF=${PROVISION_REF_IN}

USER root

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# lxqt + xrdp + 中文輸入法 + WM config 由 provision 統一維護
#（含 xorgxrdp、xtightvncviewer、startwm.sh chmod、Xwrapper / pam_env guards、
#  fcitx5 lxqt config、清理 lxqt 不需要的 desktop entries 等）
# 沿用 base sshd image 的 bigred user / passwd,避免 lxqt.txt 預設值覆寫密碼
RUN \
    export XRDP_USER=bigred XRDP_PASSWD=bigred && \
    curl -fsSL https://gitlab.com/flysangel/provision/raw/${PROVISION_REF}/ubuntu/package/lxqt/lxqt.txt | bash

# image 個性:bigred 的 ssh authorized_keys(私鑰 Phase 3a 起 runtime 注入) + dbus machine-id(runtime 啟動 dbus 需要)
# demo 公鑰刻意入庫供 image-time COPY，對應私鑰已移除，runtime 由 K8s Secret 注入。
COPY --chmod=0700 --chown=bigred:bigred home/bigred/.ssh /home/bigred/.ssh
RUN \
    dbus-uuidgen --ensure=/etc/machine-id && \
    ln -sf /etc/machine-id /var/lib/dbus/machine-id

USER bigred
WORKDIR /home/bigred

# CMD 的啟動序不能換，且與 bin/k8sadm-entry.sh 是同一段，改一邊要同步另一邊。
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD [ \
    "/bin/bash", \
    "-c", \
    " \
    # xrdp
    sudo rm -rf /run/dbus/pid /var/run/xrdp/xrdp-sesman.pid /var/run/xrdp/xrdp.pid ;\
    sudo /usr/bin/dbus-daemon --system --fork ;\
    sudo /usr/sbin/xrdp-sesman ;\
    sudo /usr/sbin/xrdp ;\
    # sshd
    sudo install -m 0755 -d /run/sshd && \
    sudo /usr/sbin/sshd -D -e ;\
    "]
