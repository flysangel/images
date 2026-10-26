# bigdata jdk 樣板：OpenJDK 8（Eclipse Temurin 8u492，Adoptium 官方）；FROM images ubuntu:sshd（含 bigred/sshd）
ARG REGISTRY_PREFIX
ARG UBUNTU_SERVICE_VERSION
FROM ${REGISTRY_PREFIX}/ubuntu:sshd-${UBUNTU_SERVICE_VERSION}

USER root

ARG JAVA_VERSION
ARG JAVA_HOME=/opt/${JAVA_VERSION}
ARG JAVA_URL
ARG JAVA_SHA256

# Install packages（官方源 Adoptium + sha256 校驗；curl/sha256sum 由 ubuntu base 提供）
RUN \
    curl -fsSL "${JAVA_URL}" -o /jdk.tar.gz && \
    echo "${JAVA_SHA256}  /jdk.tar.gz" | sha256sum -c - && \
    tar xf /jdk.tar.gz -C /opt && \
    chown -R root:root /opt && \
    rm -f /jdk.tar.gz

# Set environment variables（寫入 /etc/profile.d，讓 ssh 登入 shell 也吃到 JAVA_HOME/PATH；ENV 只涵蓋非登入的 exec 環境）
RUN \
    echo export JAVA_HOME=${JAVA_HOME} | tee /etc/profile.d/java-env.sh && \
    echo export PATH='${PATH}':${JAVA_HOME}/bin | tee -a /etc/profile.d/java-env.sh

USER bigred
WORKDIR /home/bigred

ENV \
    JAVA_HOME=${JAVA_HOME} \
    PATH=${PATH}:${JAVA_HOME}/bin

# 複製 hconfig 工具（不是設定檔；由 CMD 啟動時呼叫來 render 設定 /conf→/opt）
COPY --chmod=0755 bin/hconfig /bin/hconfig

# Configure command（hconfig render /conf→/opt；jdk 無 daemon，僅 sshd）
CMD ["/bin/bash", "-c", "hconfig; sudo /usr/sbin/sshd -D"]
