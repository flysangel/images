# alpine sshd 樣板:openssh-server + bigred user + sshenv + sudo
ARG ALPINE_BASE_IMAGE
FROM ${ALPINE_BASE_IMAGE}

# 釘版穿透:provision 二跳腳本繼承此 ENV(不落回 main)
ARG PROVISION_REF_IN
ENV PROVISION_REF=${PROVISION_REF_IN}

USER root

# pipefail:下方三個 curl | bash 任一段失敗即中止 RUN（否則 curl 失敗會被 bash 吞掉、建置仍算成功）
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# [hadolint] warning: Pin versions in apk add. Instead of `apk add <package>` use `apk add <package>=<version>` (DL3018)
# hadolint ignore=DL3018
RUN \
    apk add --no-cache --update-cache openssh-server && \
    curl -fsSL https://gitlab.com/flysangel/provision/raw/${PROVISION_REF}/alpine/system/bigred/bigred.txt | bash && \
    curl -fsSL https://gitlab.com/flysangel/provision/raw/${PROVISION_REF}/alpine/system/sshenv/sshenv.txt | bash && \
    curl -fsSL https://gitlab.com/flysangel/provision/raw/${PROVISION_REF}/alpine/system/sudopw/sudopw.txt | bash

USER bigred
WORKDIR /home/bigred

ENTRYPOINT ["/sbin/tini", "--"]
CMD [ \
    "/bin/bash", \
    "-c", \
    " \
    sudo /usr/sbin/sshd -D ;\
    "]
