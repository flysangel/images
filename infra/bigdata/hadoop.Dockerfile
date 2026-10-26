# bigdata hadoop 樣板：Hadoop（版本由 HADOOP_DIR 注入）+ 原生壓縮/加密庫（archive.apache.org 官方 + sha512）；FROM bigdata:jdk
ARG REGISTRY_PREFIX
ARG SERVICE_VERSION
FROM ${REGISTRY_PREFIX}/bigdata:jdk-${SERVICE_VERSION}

USER root

ARG HADOOP_VERSION
ARG HADOOP_HOME=/opt/${HADOOP_VERSION}
ARG HADOOP_URL
ARG HADOOP_SHA512

# Install dependencies（ubuntu/apt 原生庫）
# hadolint ignore=DL3008
RUN \
    apt update --fix-missing && \
    apt install -y zstd libbz2-dev libssl-dev libisal-dev

# Install packages（官方源 + sha512 校驗）
RUN \
    curl -fsSL "${HADOOP_URL}" -o /pkg.tgz && \
    echo "${HADOOP_SHA512}  /pkg.tgz" | sha512sum -c - && \
    tar xf /pkg.tgz -C /opt && \
    chown -R root:root /opt && \
    rm -f /pkg.tgz

# 寫入 /etc/profile.d：CMD 以 sshd 常駐，SSH 登入 shell 不繼承 Docker ENV，需靠 profile.d 補上 HADOOP_HOME/PATH
RUN \
    echo export HADOOP_HOME=${HADOOP_HOME} | tee /etc/profile.d/hadoop-env.sh && \
    echo export PATH='${PATH}':${HADOOP_HOME}/bin:${HADOOP_HOME}/sbin | tee -a /etc/profile.d/hadoop-env.sh

USER bigred
WORKDIR /home/bigred

ENV \
    HADOOP_HOME=${HADOOP_HOME} \
    PATH=${PATH}:${HADOOP_HOME}/bin:${HADOOP_HOME}/sbin

# 複製 Hadoop 設定與啟停腳本（hdstart/hdstop）
COPY --chmod=0755 conf/hadoop /conf/${HADOOP_VERSION}
COPY --chmod=0755 bin/hdstart /bin/hdstart
COPY --chmod=0755 bin/hdstop /bin/hdstop

# 啟動：hconfig render 設定 → hdstart 起 HDFS/YARN；sshd -D 前景常駐保命
CMD ["/bin/bash", "-c", "hconfig; hdstart; sudo /usr/sbin/sshd -D"]
