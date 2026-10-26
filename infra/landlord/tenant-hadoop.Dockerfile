# landlord tenant-hadoop 樣板：多租戶 hadoop client（FROM bigdata:dtc-ha = is-a dtc client + 隔離/審計層）
# kubectl 走 provision 釘版（非 curl 浮動）；重用既有 log_client/template
ARG REGISTRY_PREFIX
ARG BIGDATA_SERVICE_VERSION
FROM ${REGISTRY_PREFIX}/bigdata:dtc-ha-${BIGDATA_SERVICE_VERSION}

# 釘版穿透:provision 二跳腳本繼承此 ENV
ARG PROVISION_REF_IN
ENV PROVISION_REF=${PROVISION_REF_IN}
USER root
# hadolint ignore=DL3008
RUN \
    apt update --fix-missing && \
    apt install -y default-mysql-client fuse-overlayfs podman

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN \
    curl -fsSL https://gitlab.com/flysangel/provision/raw/${PROVISION_REF}/ubuntu/package/kubectl/kubectl.txt | bash

COPY --chmod=0755 bin/tenant/log_client /bin/log_client
COPY --chmod=0755 bin/tenant/template /bin/template
# log_client 常駐（& 不是可選）；hconfig 渲染 hadoop 設定、hvrc 寫 hiverc，都在 sshd 之前完成。
CMD ["/bin/bash", "-c", "/bin/log_client & hconfig; hvrc; /usr/sbin/sshd -D"]
