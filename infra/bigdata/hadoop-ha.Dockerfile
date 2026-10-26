# bigdata hadoop-ha 樣板：HDFS NameNode HA(QJM/ZKFC/sshfence) + YARN RM HA；FROM bigdata:hadoop（re-layer，無新 tarball）
ARG REGISTRY_PREFIX
ARG SERVICE_VERSION
FROM ${REGISTRY_PREFIX}/bigdata:hadoop-${SERVICE_VERSION}

USER root

ARG HADOOP_VERSION

# HA 工具（ncurses-bin=tput；psmisc=fuser/killall，fencing 用）
# hadolint ignore=DL3008
RUN \
    apt update --fix-missing && \
    apt install -y ncurses-bin psmisc

# 清掉 base（單機 hadoop）繼承的單機 conf/bin
RUN \
    rm -rf /conf/${HADOOP_VERSION} && \
    rm -f /bin/hdstart /bin/hdstop

# passwordless ssh（NameNode 間 sshfence 用）；-m PEM 產生舊式 PEM 私鑰，否則 sshfence 的 JSch 讀不了 OpenSSH 新格式金鑰
USER bigred
WORKDIR /home/bigred
RUN \
    rm -rf ~/.ssh && \
    ssh-keygen -t rsa -m PEM -P '' -f ~/.ssh/id_rsa && \
    cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys

# HA conf/bin（來源改名避撞，容器內路徑與單機一致，hconfig/CMD 不變）
COPY --chmod=0755 conf/hadoop-ha /conf/${HADOOP_VERSION}
COPY --chmod=0755 bin/hdstart-ha /bin/hdstart
COPY --chmod=0755 bin/hdstop-ha /bin/hdstop

# 啟動：hconfig 設定、hdstart 起 HA；sshd -D 前景常駐（保命兼供 sshfence 連線）
CMD ["/bin/bash", "-c", "hconfig; hdstart; sudo /usr/sbin/sshd -D"]
