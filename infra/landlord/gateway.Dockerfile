# landlord gateway 樣板：SSH 前門（adduser 多工器，login sshpass 跳對應 tenant pod）；FROM alpine:sshd
ARG REGISTRY_PREFIX
ARG ALPINE_SERVICE_VERSION
FROM ${REGISTRY_PREFIX}/alpine:sshd-${ALPINE_SERVICE_VERSION}
USER root
# [hadolint] warning: Pin versions in apk add. Instead of `apk add <package>` use `apk add <package>=<version>` (DL3018)
# hadolint ignore=DL3018
RUN \
    apk add --no-cache --update-cache sshpass

COPY --chmod=0755 bin/gateway/adduser /bin/adduser
# 先跑 adduser 整份覆寫 /etc/profile 並建完帳號，sshd 才收連線；順序不能換，否則登入時 profile 還是 base 的版本。
CMD ["/bin/bash", "-c", "/bin/adduser; /usr/sbin/sshd -D"]
