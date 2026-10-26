# bigdata hive-ha 樣板：疊 HA hadoop client conf（nameservice 解析）+ passwordless ssh；FROM bigdata:hive，繼承 hive bins
ARG REGISTRY_PREFIX
ARG SERVICE_VERSION
FROM ${REGISTRY_PREFIX}/bigdata:hive-${SERVICE_VERSION}

USER root

ARG HADOOP_VERSION

# hadolint ignore=DL3008
RUN \
    apt update --fix-missing && \
    apt install -y ncurses-bin psmisc

RUN \
    rm -rf /conf/${HADOOP_VERSION}

USER bigred
WORKDIR /home/bigred

RUN \
    rm -rf ~/.ssh && \
    ssh-keygen -t rsa -m PEM -P '' -f ~/.ssh/id_rsa && \
    cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys

# HA hadoop conf（無 bin override，繼承 base hive 的 hv*）
COPY --chmod=0755 conf/hadoop-ha /conf/${HADOOP_VERSION}

# 啟動流程：hconfig 產生設定 → hvstart/hvrc 起 hive → sshd -D 前景常駐撐住容器
CMD ["/bin/bash", "-c", "hconfig; hvstart; hvrc; sudo /usr/sbin/sshd -D"]
