# bigdata spark 樣板：Spark 3.5.1-bin-hadoop3-scala2.13（archive.apache.org 官方 + sha512）；FROM bigdata:hadoop
ARG REGISTRY_PREFIX
ARG SERVICE_VERSION
FROM ${REGISTRY_PREFIX}/bigdata:hadoop-${SERVICE_VERSION}

USER root

ARG SPARK_VERSION
ARG SPARK_HOME=/opt/${SPARK_VERSION}
ARG SPARK_URL
ARG SPARK_SHA512

# Install packages（官方源 + sha512 校驗）
RUN \
    curl -fsSL "${SPARK_URL}" -o /pkg.tgz && \
    echo "${SPARK_SHA512}  /pkg.tgz" | sha512sum -c - && \
    tar xf /pkg.tgz -C /opt && \
    chown -R root:root /opt && \
    rm -f /pkg.tgz

# 寫進 /etc/profile.d：SSH 登入 shell 才載得到 SPARK_HOME／PATH（下方 ENV 只作用於容器主行程）
RUN \
    echo export SPARK_HOME=${SPARK_HOME} | tee /etc/profile.d/spark-env.sh && \
    echo export PATH='${PATH}':${SPARK_HOME}/bin:${SPARK_HOME}/sbin | tee -a /etc/profile.d/spark-env.sh

USER bigred
WORKDIR /home/bigred

ENV \
    SPARK_HOME=${SPARK_HOME} \
    PATH=${PATH}:${SPARK_HOME}/bin:${SPARK_HOME}/sbin

COPY --chmod=0755 conf/spark /conf/${SPARK_VERSION}

# Configure command（spark 無常駐 daemon，僅 sshd）
CMD ["/bin/bash", "-c", "hconfig; sudo /usr/sbin/sshd -D"]
