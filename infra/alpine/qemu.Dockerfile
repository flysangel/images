# alpine qemu 樣板:qemu-img + system-x86_64 + modules
ARG REGISTRY_PREFIX
ARG SERVICE_VERSION
FROM ${REGISTRY_PREFIX}/alpine:sshd-${SERVICE_VERSION}

USER root

# [hadolint] warning: Pin versions in apk add. Instead of `apk add <package>` use `apk add <package>=<version>` (DL3018)
# hadolint ignore=DL3018
RUN \
    apk add --no-cache --update-cache qemu-img qemu-system-x86_64 qemu-modules

USER bigred
WORKDIR /home/bigred

ENTRYPOINT ["/sbin/tini", "--"]
CMD [ \
    "/bin/bash", \
    "-c", \
    " \
    sudo /usr/sbin/sshd -D -e ;\
    "]
