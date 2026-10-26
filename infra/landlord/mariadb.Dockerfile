# landlord mariadb 樣板：審計 DB（history+inotify 表）；FROM library/mariadb（不釘版＝沿 hiveDB/gmm 慣例）
ARG REGISTRY_PREFIX
# hadolint ignore=DL3006
FROM ${REGISTRY_PREFIX}/library/mariadb

COPY --chmod=0644 conf/mariadb/initdb/initdb.sql /docker-entrypoint-initdb.d/initdb.sql
