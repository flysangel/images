# bigdata kafka 樣板：Kafka 3.7.0 (Scala 2.13)（archive.apache.org 官方 + sha512）；FROM bigdata:jdk
ARG REGISTRY_PREFIX
ARG SERVICE_VERSION
FROM ${REGISTRY_PREFIX}/bigdata:jdk-${SERVICE_VERSION}

USER root

ARG KAFKA_VERSION
ARG KAFKA_HOME=/opt/${KAFKA_VERSION}
ARG KAFKA_URL
ARG KAFKA_SHA512

# Install packages（官方源 + sha512 校驗）
RUN \
    curl -fsSL "${KAFKA_URL}" -o /pkg.tgz && \
    echo "${KAFKA_SHA512}  /pkg.tgz" | sha512sum -c - && \
    tar xf /pkg.tgz -C /opt && \
    chown -R root:root /opt && \
    rm -f /pkg.tgz

# Set environment variables（寫入 profile.d 供 sshd 登入 shell 載入，與下方 ENV 並存勿刪）
RUN \
    echo export KAFKA_HOME=${KAFKA_HOME} | tee /etc/profile.d/kafka-env.sh && \
    echo export PATH='${PATH}':${KAFKA_HOME}/bin:${KAFKA_HOME}/sbin | tee -a /etc/profile.d/kafka-env.sh

USER bigred
WORKDIR /home/bigred

ENV \
    KAFKA_HOME=${KAFKA_HOME} \
    PATH=${PATH}:${KAFKA_HOME}/bin:${KAFKA_HOME}/sbin

# Copy configuration files
COPY --chmod=0755 conf/kafka /conf/${KAFKA_VERSION}
COPY --chmod=0755 bin/kfstart /bin/kfstart
COPY --chmod=0755 bin/kfstop /bin/kfstop

# Configure command
CMD ["/bin/bash", "-c", "hconfig; kfstart; sudo /usr/sbin/sshd -D"]
