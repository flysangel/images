# gmm mariadb 樣板:基於 upstream mariadb,initdb 注入 guacamole schema

ARG REGISTRY_PREFIX
ARG GUACAMOLE_VERSION
ARG INITDB_IMAGE=${REGISTRY_PREFIX}/guacamole/guacamole:${GUACAMOLE_VERSION}

# [hadolint] warning: Always tag the version of an image explicitly (DL3006)
# hadolint ignore=DL3006
FROM ${INITDB_IMAGE} AS initdb

# [hadolint] warning: Last USER should not be root (DL3002)
# hadolint ignore=DL3002
USER root

WORKDIR /init

RUN \
    /opt/guacamole/bin/initdb.sh --mysql > /init/initdb.sql

# ---
# [hadolint] warning: Always tag the version of an image explicitly (DL3006)
# hadolint ignore=DL3006
FROM ${REGISTRY_PREFIX}/library/mariadb

# initdb.sql 只有建表語句，沒有 CREATE DATABASE：部署必須設 MARIADB_DATABASE，且上游 entrypoint 只在 datadir 為空時執行它。
COPY --from=initdb /init/initdb.sql /docker-entrypoint-initdb.d
