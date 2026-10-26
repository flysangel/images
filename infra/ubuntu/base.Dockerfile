# ubuntu base 樣板:apt-get 裝 ca-certificates/curl,跑 provision 的 base/ntp/locale 設定
# 上游映像由 FROM ${LIBRARY_UBUNTU_IMAGE} 供給（catalog.yaml 的 digest），不再注入 BASE

ARG LIBRARY_UBUNTU_IMAGE
FROM ${LIBRARY_UBUNTU_IMAGE}
# 釘版穿透:provision 二跳腳本繼承此 ENV(不落回 main)
ARG PROVISION_REF_IN
ENV PROVISION_REF=${PROVISION_REF_IN}

USER root

# pipefail 護欄:讓下方 curl | bash 的 curl 失敗即中止,不讓壞映像靜默過關
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# [hadolint] warning: Pin versions in apt get install. Instead of `apt-get install <package>` use `apt-get install <package>=<version>` (DL3008)
# hadolint ignore=DL3008
RUN \
    apt-get update --fix-missing && \
    apt-get install -y --no-install-recommends ca-certificates curl && \
    curl -fsSL https://gitlab.com/flysangel/provision/raw/${PROVISION_REF}/ubuntu/system/base/base.txt | bash && \
    apt-get autoremove -y && \
    apt-get clean -y && \
    rm -rf /var/cache/apt/archives

RUN \
    curl -fsSL https://gitlab.com/flysangel/provision/raw/${PROVISION_REF}/ubuntu/system/ntp/ntp.txt | bash

RUN \
    curl -fsSL https://gitlab.com/flysangel/provision/raw/${PROVISION_REF}/ubuntu/system/locale/locale.txt | bash

ENV LANG=en_US.UTF-8

# [hadolint] warning: Last USER should not be root (DL3002)
# hadolint ignore=DL3002
USER root
WORKDIR /root

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD [ \
    "/bin/bash", \
    "-c", \
    " \
    sleep infinity;\
    "]
