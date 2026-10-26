# bigdata hiveDB 樣板：Hive metastore 後端 DB；FROM library/mariadb + 自家 init SQL（解耦 web.flymks，提交進 repo）
ARG REGISTRY_PREFIX
# hadolint ignore=DL3006
FROM ${REGISTRY_PREFIX}/library/mariadb

# 自家 init SQL：授權 hive user + binlog_format=MIXED + sql_mode=NO_BACKSLASH_ESCAPES（修 Hive LIKE ESCAPE bug）
COPY --chmod=0644 conf/hiveDB/hive-patch.mysql.sql /docker-entrypoint-initdb.d/hive-patch.mysql.sql

RUN \
    chmod -R 775 /docker-entrypoint-initdb.d
