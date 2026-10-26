# open-webui dbadm 樣板:基於 library/alpine,裝 sqlite/apache2-utils/uuidgen 等維運工具 + 帳號管理 helper
# 執行期要設 SQLITE_DB 並把 open-webui 的 sqlite 檔掛進容器，映像本身不設也不掛；helper 腳本靠它找資料庫。
ARG REGISTRY_PREFIX
ARG ALPINE_BASE
FROM ${REGISTRY_PREFIX}/library/alpine:${ALPINE_BASE}

USER root

COPY --chmod=0755 adduser.sh /bin/adduser.sh
COPY --chmod=0755 deluser.sh /bin/deluser.sh
COPY --chmod=0755 lsuser.sh /bin/lsuser.sh
COPY --chmod=0755 resetpasswd.sh /bin/resetpasswd.sh

# 套件對應腳本的相依：sqlite 給 sqlite3、apache2-utils 給 htpasswd、uuidgen 給 id 與 api_key；sudo、nano 給人進容器手動維運。
# [hadolint] warning: Pin versions in apk add. Instead of `apk add <package>` use `apk add <package>=<version>` (DL3018)
# hadolint ignore=DL3018
RUN \
    apk add --no-cache --update-cache \
    sudo bash nano \
    sqlite apache2-utils uuidgen \
    tini

ENV LANG=en_US.UTF-8

# [hadolint] warning: Last USER should not be root (DL3002)
# hadolint ignore=DL3002
USER root
WORKDIR /root

ENTRYPOINT ["/sbin/tini", "--"]
# 映像只為 exec 腳本活著，CMD 用 exec 形式讓 tini 直接管 sleep。
CMD ["sleep", "infinity"]
