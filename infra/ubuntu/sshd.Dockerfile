# ubuntu sshd 樣板:openssh-server + bigred user + sudo
ARG REGISTRY_PREFIX
ARG SERVICE_VERSION
FROM ${REGISTRY_PREFIX}/ubuntu:base-${SERVICE_VERSION}

# 釘版穿透:provision 二跳腳本繼承此 ENV(不落回 main)
ARG PROVISION_REF_IN
ENV PROVISION_REF=${PROVISION_REF_IN}

USER root

# 開 pipefail:下方 curl | bash 若 curl 失敗才會中斷建置(預設只看管線末端 bash 的結果)
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# [hadolint] warning: Pin versions in apt get install. Instead of `apt-get install <package>` use `apt-get install <package>=<version>` (DL3008)
# hadolint ignore=DL3008
RUN \
    apt-get update --fix-missing && \
    apt-get install -y --no-install-recommends openssh-server && \
    curl -fsSL https://gitlab.com/flysangel/provision/raw/${PROVISION_REF}/ubuntu/system/bigred/bigred.txt | bash && \
    curl -fsSL https://gitlab.com/flysangel/provision/raw/${PROVISION_REF}/ubuntu/system/sshenv/sshenv.txt | bash && \
    curl -fsSL https://gitlab.com/flysangel/provision/raw/${PROVISION_REF}/ubuntu/system/sudopw/sudopw.txt | bash && \
    apt-get autoremove -y && \
    apt-get clean -y && \
    rm -rf /var/cache/apt/archives

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
