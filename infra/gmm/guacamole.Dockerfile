# gmm guacamole 樣板:custom logo + ext + home.html;maven multi-stage build

ARG REGISTRY_PREFIX
ARG ALPINE_SERVICE_VERSION
ARG UPSTREAM_DOCKER
ARG DOWNLOADER_IMAGE=${REGISTRY_PREFIX}/alpine:base-${ALPINE_SERVICE_VERSION}
ARG GUACAMOLE_VERSION
# TOMCAT_VERSION 與 TOMCAT_JRE 照抄上游，帶預設值，不受 versions.conf 管。
ARG TOMCAT_VERSION=9
ARG TOMCAT_JRE=jdk21

# ---
# [hadolint] warning: Always tag the version of an image explicitly (DL3006)
# hadolint ignore=DL3006
FROM ${DOWNLOADER_IMAGE} AS downloader

ARG GUACAMOLE_VERSION

ENV GUACAMOLE_HOME=/opt/guacamole

# [hadolint] warning: Last USER should not be root (DL3002)
# hadolint ignore=DL3002
USER root

RUN \
    curl -fsSLO https://github.com/apache/guacamole-client/archive/refs/tags/${GUACAMOLE_VERSION}.tar.gz && \
    tar xf ${GUACAMOLE_VERSION}.tar.gz

# ---
# https://github.com/apache/guacamole-client/blob/1.6.0/Dockerfile
# 自家加的段落用 ### [Custom] 前綴，其餘與上游同步；升 Guacamole 版本先 diff 上游的 Dockerfile。
# maven 與下方的 tomcat 走 UPSTREAM_DOCKER 直連上游，sync/repository/ 沒有這兩顆的同步規則。
# 改成 REGISTRY_PREFIX 之前，要先補同步規則並實際同步過。
# （這段註解不寫 $ 加大括號的寫法：family-lint.py 連註解也掃，會誤判成 stage 內文用了 ARG。）
FROM ${UPSTREAM_DOCKER}/library/maven:3-eclipse-temurin-21 AS builder

ARG GUACAMOLE_VERSION

ENV GUACAMOLE_HOME=/opt/guacamole

# Use Mozilla's Firefox PPA (newer Ubuntu lacks a "firefox-esr" package and
# provides only a transitional "firefox" package that actually requires Snap
# and thus can't be used within Docker)
# [hadolint] warning: Pin versions in apt get install. Instead of `apt-get install <package>` use `apt-get install <package>=<version>` (DL3008)
# hadolint ignore=DL3008
RUN \
    apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends software-properties-common && \
    add-apt-repository -y ppa:mozillateam/ppa

### [Custom] Explicitly prefer packages from the Firefox PPA
COPY --from=downloader /root/guacamole-client-${GUACAMOLE_VERSION}/guacamole-docker/mozilla-firefox.pref /etc/apt/preferences.d/

# Install firefox browser for sake of JavaScript unit tests
# [hadolint] warning: Pin versions in apt get install. Instead of `apt-get install <package>` use `apt-get install <package>=<version>` (DL3008)
# hadolint ignore=DL3008
RUN \
    apt-get update && \
    apt-get install -y --no-install-recommends firefox

# Arbitrary arguments that can be passed to the maven build. By default, an
# argument will be provided to explicitly unskip any skipped tests. To, for
# example, allow the building of the RADIUS auth extension, pass a build profile
# as well: `--build-arg MAVEN_ARGUMENTS="-P lgpl-extensions -DskipTests=false"`.
ARG MAVEN_ARGUMENTS="-DskipTests=false"

# 以下帶預設值的 ARG 照抄上游，不受 versions.conf 管；升 mariadb 要對 MYSQL_JDBC_VERSION。
# Versions of JDBC drivers to bundle within image
ARG MSSQL_JDBC_VERSION=9.4.1
ARG MYSQL_JDBC_VERSION=8.3.0
ARG PGSQL_JDBC_VERSION=42.7.2

# Build environment variables
ENV \
    BUILD_DIR=/tmp/guacamole-docker-BUILD

### [Custom] Add configuration scripts
COPY --from=downloader /root/guacamole-client-${GUACAMOLE_VERSION}/guacamole-docker/bin ${GUACAMOLE_HOME}/bin
COPY --from=downloader /root/guacamole-client-${GUACAMOLE_VERSION}/guacamole-docker/build.d ${GUACAMOLE_HOME}/build.d
COPY --from=downloader /root/guacamole-client-${GUACAMOLE_VERSION}/guacamole-docker/entrypoint.d ${GUACAMOLE_HOME}/entrypoint.d
COPY --from=downloader /root/guacamole-client-${GUACAMOLE_VERSION}/guacamole-docker/environment ${GUACAMOLE_HOME}/environment

### [Custom] Copy source to container for sake of build
COPY --from=downloader /root/guacamole-client-${GUACAMOLE_VERSION} ${BUILD_DIR}

### [Custom] Change home.html
# 拿掉上游首頁的 recent connections 區塊，只留 all connections；樣板要進 maven 建置，COPY 必須排在 build-guacamole.sh 之前。
# guacamole-client-*/guacamole/src/main/frontend/src/app/home/templates/home.html
COPY --chmod=0644 ./home/home.html ${BUILD_DIR}/guacamole/src/main/frontend/src/app/home/templates/home.html

### [Custom] Run the build itself
RUN \
    ${GUACAMOLE_HOME}/bin/build-guacamole.sh ${BUILD_DIR} ${GUACAMOLE_HOME}

### [Custom] Run build custom logo
COPY --chmod=0755 ./ext ${GUACAMOLE_HOME}/ext
COPY --chmod=0755 ./images ${GUACAMOLE_HOME}/images

RUN \
    ${GUACAMOLE_HOME}/ext/guacamole-ext.sh && \
    rm -rf ${GUACAMOLE_HOME}/ext && \
    rm -rf ${GUACAMOLE_HOME}/images

# ---
# For the runtime image, we start with the official Tomcat distribution
FROM ${UPSTREAM_DOCKER}/library/tomcat:${TOMCAT_VERSION}-${TOMCAT_JRE}

ARG GUACAMOLE_VERSION

ENV GUACAMOLE_HOME=/opt/guacamole

# Install XMLStarlet for server.xml alterations and unzip for LOGBACK_LEVEL case
# [hadolint] warning: Pin versions in apt get install. Instead of `apt-get install <package>` use `apt-get install <package>=<version>` (DL3008)
# hadolint ignore=DL3008
RUN \
    apt-get update -qq && \
    apt-get install -y --no-install-recommends xmlstarlet unzip && \
    rm -rf /var/lib/apt/lists/*

# This is where the build artifacts go in the runtime image
WORKDIR ${GUACAMOLE_HOME}

# Copy artifacts from builder image into this image
COPY --from=builder ${GUACAMOLE_HOME} .

### [Custom] Create a new user guacamole same with ext auto create
ARG UID=1001
ARG GID=1001

RUN \
    userdel -r ubuntu && \
    groupadd --gid ${GID} guacamole && \
    useradd --system --create-home --shell /usr/sbin/nologin --uid ${UID} --gid ${GID} guacamole

### [Custom] extensions
RUN \
    mkdir -p ${GUACAMOLE_HOME}/extensions && \
    chown -R guacamole:guacamole ${GUACAMOLE_HOME}/extensions

USER guacamole

# Environment variable defaults
# 設定全靠執行期環境變數與 *_FILE 變體，映像內沒有 guacamole.properties。
ENV \
    ENABLE_FILE_ENVIRONMENT_PROPERTIES=true

# Start Guacamole under Tomcat, listening on 0.0.0.0:8080
EXPOSE 8080

# LOGO 由執行期環境變數指定要啟用的 logo extension jar(未設定時 cp 失敗,entrypoint 照常啟動、無自訂 logo)
# 可用值等於 images/ 的目錄名；每個目錄固定 logo.png、logo-64.png、logo-144.png 三個檔，檔名由 ext/guac-manifest.json 寫死。
CMD [ \
    "/bin/bash", \
    "-c", \
    " \
    cp ./guacamole-ext/${LOGO}.jar ./extensions/guacamole-ext.jar ;\
    ./bin/entrypoint.sh ;\
    "]
