# bigdata hiveDB 樣板：Hive metastore 後端 DB；FROM library/mariadb + 自家 init SQL（解耦 web.flymks，提交進 repo）
# 上游 mariadb 由 catalog.yaml 的 upstream LIBRARY_MARIADB 釘 digest；它同步的是 latest，換 digest 等於換 base。
ARG LIBRARY_MARIADB_IMAGE

# [hadolint] warning: Always tag the version of an image explicitly (DL3006)
# hadolint ignore=DL3006
FROM ${LIBRARY_MARIADB_IMAGE}

# 自家 init SQL：授權 hive user + binlog_format=MIXED + sql_mode=NO_BACKSLASH_ESCAPES（修 Hive LIKE ESCAPE bug）
COPY --chmod=0644 conf/hiveDB/hive-patch.mysql.sql /docker-entrypoint-initdb.d/hive-patch.mysql.sql

RUN \
    chmod -R 775 /docker-entrypoint-initdb.d
