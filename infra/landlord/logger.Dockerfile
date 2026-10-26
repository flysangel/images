# landlord logger 樣板：session 審計 sink（log_server nc :5566 → mariadb history/inotify）；FROM alpine:base
ARG REGISTRY_PREFIX
ARG ALPINE_SERVICE_VERSION
FROM ${REGISTRY_PREFIX}/alpine:base-${ALPINE_SERVICE_VERSION}
USER root
# hadolint ignore=DL3018
RUN \
    apk add --no-cache --update-cache mysql-client
COPY --chmod=0755 bin/logger/log_server /bin/log_server
CMD ["/bin/bash", "-c", "/bin/log_server"]
