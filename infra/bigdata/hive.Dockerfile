# bigdata hive 樣板：Hive 4.0.0（archive.apache.org + sha256）+ MariaDB JDBC 2.7.12（Maven Central + sha1）；FROM bigdata:hadoop
ARG REGISTRY_PREFIX
ARG SERVICE_VERSION
FROM ${REGISTRY_PREFIX}/bigdata:hadoop-${SERVICE_VERSION}

USER root

ARG HIVE_VERSION
ARG HIVE_HOME=/opt/${HIVE_VERSION}
ARG HIVE_URL
ARG HIVE_SHA256
ARG JDBC_JAR
ARG JDBC_URL
ARG JDBC_SHA1

# Install packages（hive 官方 + sha256；mariadb-jdbc Maven + sha1，置入 $HIVE_HOME/lib）
RUN \
    curl -fsSL "${HIVE_URL}" -o /hive.tgz && \
    echo "${HIVE_SHA256}  /hive.tgz" | sha256sum -c - && \
    tar xf /hive.tgz -C /opt && \
    curl -fsSL "${JDBC_URL}" -o "${HIVE_HOME}/lib/${JDBC_JAR}" && \
    echo "${JDBC_SHA1}  ${HIVE_HOME}/lib/${JDBC_JAR}" | sha1sum -c - && \
    chown -R root:root /opt && \
    chmod -R 775 ${HIVE_HOME}/lib && \
    rm -f /hive.tgz

# 寫入 /etc/profile.d 供 SSH 登入 shell 取用（下方 ENV 只作用於容器主行程，登入 shell 不繼承）
RUN \
    echo export HIVE_HOME=${HIVE_HOME} | tee /etc/profile.d/hive-env.sh && \
    echo export PATH='${PATH}':${HIVE_HOME}/bin:${HIVE_HOME}/sbin | tee -a /etc/profile.d/hive-env.sh

USER bigred
WORKDIR /home/bigred

ENV \
    HIVE_HOME=${HIVE_HOME} \
    PATH=${PATH}:${HIVE_HOME}/bin:${HIVE_HOME}/sbin

# Copy configuration files
COPY --chmod=0755 conf/hive /conf/${HIVE_VERSION}
COPY --chmod=0755 bin/hvrc /bin/hvrc
COPY --chmod=0755 bin/hvsql /bin/hvsql
COPY --chmod=0755 bin/hvstart /bin/hvstart
COPY --chmod=0755 bin/hvstop /bin/hvstop

# Configure command
CMD ["/bin/bash", "-c", "hconfig; hvstart; hvrc; sudo /usr/sbin/sshd -D"]
