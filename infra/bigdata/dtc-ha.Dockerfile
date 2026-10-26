# bigdata dtc-ha 樣板（client 物件）：HA bigdata 全套用戶端（hadoop/hbase/hive/kafka/spark/zk + HA nameservice client conf）
# FROM bigdata:jdk（中性基礎，非伺服端）；平攤組裝全套套件 + conf，繼承 hconfig + COPY hvrc
ARG REGISTRY_PREFIX
ARG SERVICE_VERSION
FROM ${REGISTRY_PREFIX}/bigdata:jdk-${SERVICE_VERSION}

USER root

ARG HADOOP_VERSION
ARG HBASE_VERSION
ARG HIVE_VERSION
ARG KAFKA_VERSION
ARG SPARK_VERSION
ARG ZOOKEEPER_VERSION
ARG HADOOP_HOME=/opt/${HADOOP_VERSION}
ARG HBASE_HOME=/opt/${HBASE_VERSION}
ARG HIVE_HOME=/opt/${HIVE_VERSION}
ARG KAFKA_HOME=/opt/${KAFKA_VERSION}
ARG SPARK_HOME=/opt/${SPARK_VERSION}
ARG ZOOKEEPER_HOME=/opt/${ZOOKEEPER_VERSION}
ARG HADOOP_URL
ARG HADOOP_SHA512
ARG HBASE_URL
ARG HBASE_SHA512
ARG HIVE_URL
ARG HIVE_SHA256
ARG JDBC_JAR
ARG JDBC_URL
ARG JDBC_SHA1
ARG KAFKA_URL
ARG KAFKA_SHA512
ARG SPARK_URL
ARG SPARK_SHA512
ARG ZOOKEEPER_URL
ARG ZOOKEEPER_SHA512

# Hadoop 原生壓縮/加密庫（ubuntu/apt；同 bigdata:hadoop）
# hadolint ignore=DL3008
RUN \
    apt update --fix-missing && \
    apt install -y zstd libbz2-dev libssl-dev libisal-dev

# 全套 client 套件（官方源 + checksum；逐套件同各 bigdata 組件）
RUN \
    curl -fsSL "${HADOOP_URL}" -o /pkg.tgz && echo "${HADOOP_SHA512}  /pkg.tgz" | sha512sum -c - && tar xf /pkg.tgz -C /opt && rm -f /pkg.tgz && \
    curl -fsSL "${HBASE_URL}" -o /pkg.tgz && echo "${HBASE_SHA512}  /pkg.tgz" | sha512sum -c - && tar xf /pkg.tgz -C /opt && rm -f /pkg.tgz && \
    curl -fsSL "${HIVE_URL}" -o /hive.tgz && echo "${HIVE_SHA256}  /hive.tgz" | sha256sum -c - && tar xf /hive.tgz -C /opt && rm -f /hive.tgz && \
    curl -fsSL "${JDBC_URL}" -o "${HIVE_HOME}/lib/${JDBC_JAR}" && echo "${JDBC_SHA1}  ${HIVE_HOME}/lib/${JDBC_JAR}" | sha1sum -c - && \
    curl -fsSL "${KAFKA_URL}" -o /pkg.tgz && echo "${KAFKA_SHA512}  /pkg.tgz" | sha512sum -c - && tar xf /pkg.tgz -C /opt && rm -f /pkg.tgz && \
    curl -fsSL "${SPARK_URL}" -o /pkg.tgz && echo "${SPARK_SHA512}  /pkg.tgz" | sha512sum -c - && tar xf /pkg.tgz -C /opt && rm -f /pkg.tgz && \
    curl -fsSL "${ZOOKEEPER_URL}" -o /pkg.tgz && echo "${ZOOKEEPER_SHA512}  /pkg.tgz" | sha512sum -c - && tar xf /pkg.tgz -C /opt && rm -f /pkg.tgz && \
    chown -R root:root /opt && chmod -R 775 ${HIVE_HOME}/lib

# HOME env（全套；profile.d 供 login shell）
RUN { \
    echo "export HADOOP_HOME=${HADOOP_HOME}"; \
    echo "export HBASE_HOME=${HBASE_HOME}"; \
    echo "export HIVE_HOME=${HIVE_HOME}"; \
    echo "export KAFKA_HOME=${KAFKA_HOME}"; \
    echo "export SPARK_HOME=${SPARK_HOME}"; \
    echo "export ZOOKEEPER_HOME=${ZOOKEEPER_HOME}"; \
    echo 'export PATH=${PATH}'":${HADOOP_HOME}/bin:${HADOOP_HOME}/sbin:${HBASE_HOME}/bin:${HIVE_HOME}/bin:${KAFKA_HOME}/bin:${SPARK_HOME}/bin:${ZOOKEEPER_HOME}/bin"; \
    } | tee /etc/profile.d/dtc-env.sh

USER bigred
WORKDIR /home/bigred

ENV \
    HADOOP_HOME=${HADOOP_HOME} \
    HBASE_HOME=${HBASE_HOME} \
    HIVE_HOME=${HIVE_HOME} \
    KAFKA_HOME=${KAFKA_HOME} \
    SPARK_HOME=${SPARK_HOME} \
    ZOOKEEPER_HOME=${ZOOKEEPER_HOME} \
    PATH=${PATH}:${HADOOP_HOME}/bin:${HADOOP_HOME}/sbin:${HBASE_HOME}/bin:${HIVE_HOME}/bin:${KAFKA_HOME}/bin:${SPARK_HOME}/bin:${ZOOKEEPER_HOME}/bin

# Client conf（hadoop 用 HA nameservice 解析；其餘用 base conf）→ /conf/<version>，hconfig runtime 渲染
COPY --chmod=0755 conf/hadoop-ha /conf/${HADOOP_VERSION}
COPY --chmod=0755 conf/hbase /conf/${HBASE_VERSION}
COPY --chmod=0755 conf/hive /conf/${HIVE_VERSION}
COPY --chmod=0755 conf/kafka /conf/${KAFKA_VERSION}
COPY --chmod=0755 conf/spark /conf/${SPARK_VERSION}
COPY --chmod=0755 conf/zookeeper /conf/${ZOOKEEPER_VERSION}
# hvrc（自 hive bin）；hconfig 已自 jdk 繼承於 /bin/hconfig
COPY --chmod=0755 bin/hvrc /bin/hvrc

# Configure command（client：渲染 conf + hiverc + sshd；無 daemon）
CMD ["/bin/bash", "-c", "hconfig; hvrc; sudo /usr/sbin/sshd -D"]
