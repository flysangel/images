# 兩 stage 範例
ARG MINIO_MC_IMAGE
ARG ALPINE_SSHD_IMAGE
# hadolint ignore=DL3006
FROM ${MINIO_MC_IMAGE} AS mc

FROM ${ALPINE_SSHD_IMAGE}
USER root
ARG SEAWEEDFS_URL
ARG LOCAL_DEFAULT=y
ENV FOO=bar
COPY --from=mc /usr/bin/mc /tmp/mc
RUN curl -fsSL "${SEAWEEDFS_URL}" -o weed.tar.gz
