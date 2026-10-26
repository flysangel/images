# alpine k8sadm 樣板:基於 alpine:k8stools + 注入 kubeconfig template
ARG REGISTRY_PREFIX
ARG SERVICE_VERSION
FROM ${REGISTRY_PREFIX}/alpine:k8stools-${SERVICE_VERSION}

USER bigred
WORKDIR /home/bigred

# alpine 的 bigred 主群組是 wheel（adduser -G wheel），映像內無同名群組，不能寫 bigred:bigred
COPY --chown=bigred:wheel --chmod=0600 kube/config /home/bigred/.kube/config.tmp
COPY --chown=bigred:wheel --chmod=0755 bin/k8sadm-entry.sh /usr/local/bin/k8sadm-entry.sh

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/usr/local/bin/k8sadm-entry.sh"]
