# ubuntu knife 樣板:基於 ubuntu:sshd + net/disk diagnostics + kubectl
ARG REGISTRY_PREFIX
ARG SERVICE_VERSION
FROM ${REGISTRY_PREFIX}/ubuntu:sshd-${SERVICE_VERSION}
# 釘版穿透:provision 二跳腳本繼承此 ENV(不落回 main)
ARG PROVISION_REF_IN
ENV PROVISION_REF=${PROVISION_REF_IN}

USER root

# [hadolint] warning: Pin versions in apt get install. Instead of `apt-get install <package>` use `apt-get install <package>=<version>` (DL3008)
# hadolint ignore=DL3008
RUN \
    apt-get update --fix-missing && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    # net
    arping arptables \
    dnsutils ethtool \
    iperf3 tcpdump libpcap-dev \
    traceroute tcptraceroute \
    # disk
    coreutils fio ioping && \
    apt-get autoremove -y && \
    apt-get clean -y && \
    rm -rf /var/cache/apt/archives

# pipefail:下一個 RUN 以 curl | bash 安裝,curl 失敗即中止管線
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN \
    curl -fsSL https://gitlab.com/flysangel/provision/raw/${PROVISION_REF}/ubuntu/package/kubectl/kubectl.txt |  bash

USER bigred
WORKDIR /home/bigred

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD [ \
    "/bin/bash", \
    "-c", \
    " \
    sudo mkdir -p /run/sshd ;\
    sudo /usr/sbin/sshd -D ;\
    "]
