# alpine s3cli 樣板:multi-stage 取 minio/mc + 釘版 seaweedfs(SEAWEEDFS_URL + sha256)

ARG REGISTRY_PREFIX
ARG SERVICE_VERSION
# [hadolint] warning: Always tag the version of an image explicitly (DL3006)
# hadolint ignore=DL3006
FROM ${REGISTRY_PREFIX}/minio/mc AS mc

FROM ${REGISTRY_PREFIX}/alpine:sshd-${SERVICE_VERSION}

USER root

ARG SEAWEEDFS_URL
ARG SEAWEEDFS_SHA256

COPY --from=mc /usr/bin/mc /tmp/mc

RUN \
    install -o root -g root -m 0755 /tmp/mc /usr/local/bin/mc && \
    rm -rf /tmp/mc*

# 下方 checksum RUN 內含 pipe,先切 bash+pipefail(供 echo | sha256sum 用,亦滿足 hadolint DL4006)
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# seaweedfs 釘版 SEAWEEDFS_URL + sha256 校驗(取代 build 期 releases/latest 浮動查詢,確保映像可重現/airgap)
RUN \
    curl -fsSL "${SEAWEEDFS_URL}" -o weed.tar.gz && \
    echo "${SEAWEEDFS_SHA256}  weed.tar.gz" | sha256sum -c - && \
    tar xf weed.tar.gz && \
    install -o root -g root -m 0755 weed /usr/local/bin/weed && \
    rm -rf weed*

USER bigred
WORKDIR /home/bigred

ENTRYPOINT ["/sbin/tini", "--"]
CMD [ \
    "/bin/bash", \
    "-c", \
    " \
    sudo /usr/sbin/sshd -D ;\
    "]
