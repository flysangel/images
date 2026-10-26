# gmm guacd 樣板:基於 upstream guacd image,加 recordings 目錄

ARG REGISTRY_PREFIX
ARG GUACAMOLE_VERSION
ARG SOURCE_IMAGE=${REGISTRY_PREFIX}/guacamole/guacd:${GUACAMOLE_VERSION}

# ---
# https://github.com/apache/guacamole-server/blob/1.6.0/Dockerfile
# [hadolint] warning: Always tag the version of an image explicitly (DL3006)
# hadolint ignore=DL3006
FROM ${SOURCE_IMAGE} AS main

USER root

# 錄影 volume 要與 guacamole 共享：guacd 以 UID 1000 寫、guacamole 以 UID 1001 讀，部署時確認權限。
RUN \
    mkdir -p /var/lib/guacamole/recordings && \
    chown guacd:guacd /var/lib/guacamole/recordings

USER guacd
