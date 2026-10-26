# landlord tenant（alpine）樣板：多租戶隔離+審計（log_client）；重用 alpine:k8stools（含 sshd+kubectl+podman；kubectl provision 釘版）
ARG REGISTRY_PREFIX
ARG ALPINE_SERVICE_VERSION
FROM ${REGISTRY_PREFIX}/alpine:k8stools-${ALPINE_SERVICE_VERSION}
USER root

# hadolint ignore=DL3018
RUN \
    apk add --no-cache --update-cache mysql-client gettext inotify-tools sudo

COPY --chmod=0755 bin/tenant/log_client /bin/log_client
COPY --chmod=0755 bin/tenant/template /bin/template

# log_client 以 inotifywait 常駐永不結束，& 不是可選。
CMD ["/bin/bash", "-c", "/bin/log_client & /usr/sbin/sshd -D"]
