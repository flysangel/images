# bigdata zookeeper 樣板：ZooKeeper 3.8.4（archive.apache.org 官方 + sha512）；FROM bigdata:jdk
ARG REGISTRY_PREFIX
ARG SERVICE_VERSION
FROM ${REGISTRY_PREFIX}/bigdata:jdk-${SERVICE_VERSION}

USER root

ARG ZOOKEEPER_VERSION
ARG ZOOKEEPER_HOME=/opt/${ZOOKEEPER_VERSION}
ARG ZOOKEEPER_URL
ARG ZOOKEEPER_SHA512

# Install packages（官方源 + sha512 校驗）
RUN \
    curl -fsSL "${ZOOKEEPER_URL}" -o /pkg.tgz && \
    echo "${ZOOKEEPER_SHA512}  /pkg.tgz" | sha512sum -c - && \
    tar xf /pkg.tgz -C /opt && \
    chown -R root:root /opt && \
    rm -f /pkg.tgz

# 寫入 profile.d，供 SSH 登入 shell 載入 env（有別於下方容器 ENV）
RUN \
    echo export ZOOKEEPER_HOME=${ZOOKEEPER_HOME} | tee /etc/profile.d/zookeeper-env.sh && \
    echo export PATH='${PATH}':${ZOOKEEPER_HOME}/bin:${ZOOKEEPER_HOME}/sbin | tee -a /etc/profile.d/zookeeper-env.sh

USER bigred
WORKDIR /home/bigred

ENV \
    ZOOKEEPER_HOME=${ZOOKEEPER_HOME} \
    PATH=${PATH}:${ZOOKEEPER_HOME}/bin:${ZOOKEEPER_HOME}/sbin

# 複製設定檔與 zk 啟停腳本
COPY --chmod=0755 conf/zookeeper /conf/${ZOOKEEPER_VERSION}
COPY --chmod=0755 bin/zkstart /bin/zkstart
COPY --chmod=0755 bin/zkstop /bin/zkstop

# 前景啟動：套設定 → 啟 zk → sshd -D 保持容器存活
CMD ["/bin/bash", "-c", "hconfig; zkstart; sudo /usr/sbin/sshd -D"]
