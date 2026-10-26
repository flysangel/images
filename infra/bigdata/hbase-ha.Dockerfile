# bigdata hbase-ha 樣板：HBase 雙 master(HBASE/HBASE_STBY，ZK 選主) + 疊 HA hadoop conf；FROM bigdata:hbase
ARG REGISTRY_PREFIX
ARG SERVICE_VERSION
FROM ${REGISTRY_PREFIX}/bigdata:hbase-${SERVICE_VERSION}

USER root

ARG HADOOP_VERSION
ARG HBASE_VERSION

# hadolint ignore=DL3008
RUN \
    apt update --fix-missing && \
    apt install -y ncurses-bin psmisc

# 清掉繼承的單機 hadoop conf（來自 bigdata:hadoop）+ 單 master 啟停
RUN \
    rm -rf /conf/${HADOOP_VERSION} && \
    rm -f /bin/hbstart /bin/hbstop

# passwordless ssh
USER bigred
WORKDIR /home/bigred
RUN \
    rm -rf ~/.ssh && \
    ssh-keygen -t rsa -m PEM -P '' -f ~/.ssh/id_rsa && \
    cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys

# 疊共享 HA hadoop conf（nameservice 解析）+ 打撈的雙 master 啟停
COPY --chmod=0755 conf/hadoop-ha /conf/${HADOOP_VERSION}
# 覆寫 hbase.rootdir 走 HDFS nameservice（${HDFS}，非單一 NN:9820）——HA HDFS RPC 為 8020 且 active NN 會 failover
COPY --chmod=0644 conf/hbase-ha/conf/hbase-site.xml /conf/${HBASE_VERSION}/conf/hbase-site.xml
COPY --chmod=0755 bin/hbstart-ha /bin/hbstart
COPY --chmod=0755 bin/hbstop-ha /bin/hbstop

# Configure command（先起 HDFS 再起 HBase 雙 master）
CMD ["/bin/bash", "-c", "hconfig; hdstart; hbstart; sudo /usr/sbin/sshd -D"]
