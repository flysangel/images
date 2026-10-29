# gmm mariadb 樣板:基於 upstream mariadb,initdb 注入 guacamole schema

# initdb 取自上游 guacamole 映像，最終層是上游 mariadb，兩者由 catalog.yaml 的 upstream 釘 digest。
# 上游 mariadb 同步的是 latest，換 digest 等於換 base，見 catalog.yaml 的 LIBRARY_MARIADB。
ARG GUACAMOLE_GUACAMOLE_IMAGE
ARG LIBRARY_MARIADB_IMAGE

# [hadolint] warning: Always tag the version of an image explicitly (DL3006)
# hadolint ignore=DL3006
FROM ${GUACAMOLE_GUACAMOLE_IMAGE} AS initdb

# [hadolint] warning: Last USER should not be root (DL3002)
# hadolint ignore=DL3002
USER root

WORKDIR /init

RUN \
    /opt/guacamole/bin/initdb.sh --mysql > /init/initdb.sql

# ---
# [hadolint] warning: Always tag the version of an image explicitly (DL3006)
# hadolint ignore=DL3006
FROM ${LIBRARY_MARIADB_IMAGE}

# initdb.sql 只有建表語句，沒有 CREATE DATABASE：部署必須設 MARIADB_DATABASE，且上游 entrypoint 只在 datadir 為空時執行它。
COPY --from=initdb /init/initdb.sql /docker-entrypoint-initdb.d
