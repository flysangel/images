# bigdata hbase 樣板：HBase 2.5.8-hadoop3（archive.apache.org 官方 + sha512）；FROM bigdata:hadoop
ARG REGISTRY_PREFIX
ARG SERVICE_VERSION
FROM ${REGISTRY_PREFIX}/bigdata:hadoop-${SERVICE_VERSION}

USER root

ARG HBASE_VERSION
ARG HBASE_HOME=/opt/${HBASE_VERSION}
ARG HBASE_URL
ARG HBASE_SHA512

# Install packages（官方源 + sha512 校驗；下載檔名帶 -bin，解壓目錄不帶）
RUN \
    curl -fsSL "${HBASE_URL}" -o /pkg.tgz && \
    echo "${HBASE_SHA512}  /pkg.tgz" | sha512sum -c - && \
    tar xf /pkg.tgz -C /opt && \
    chown -R root:root /opt && \
    rm -f /pkg.tgz

# 寫進 /etc/profile.d：SSH 登入 shell 才載得到 HBASE_HOME／PATH（下方 ENV 只作用於容器主行程）
RUN \
    echo export HBASE_HOME=${HBASE_HOME} | tee /etc/profile.d/hbase-env.sh && \
    echo export PATH='${PATH}':${HBASE_HOME}/bin:${HBASE_HOME}/sbin | tee -a /etc/profile.d/hbase-env.sh

USER bigred
WORKDIR /home/bigred

ENV \
    HBASE_HOME=${HBASE_HOME} \
    PATH=${PATH}:${HBASE_HOME}/bin:${HBASE_HOME}/sbin

# 複製 HBase 設定與啟停腳本（hbstart/hbstop）
COPY --chmod=0755 conf/hbase /conf/${HBASE_VERSION}
COPY --chmod=0755 bin/hbstart /bin/hbstart
COPY --chmod=0755 bin/hbstop /bin/hbstop

# Configure command（hbase 站 hadoop 之上，先起 HDFS 再起 HBase）
CMD ["/bin/bash", "-c", "hconfig; hdstart; hbstart; sudo /usr/sbin/sshd -D"]
