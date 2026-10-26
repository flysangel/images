# rdp xfce4-k8sadm 樣板:基於 rdp:xfce4-k8stools + 注入 kubeconfig template
# 進入點 bin/k8sadm-entry.sh 合併 kubeconfig 渲染 + 桌面啟動(xrdp/sesman/sshd)
ARG REGISTRY_PREFIX
ARG SERVICE_VERSION
FROM ${REGISTRY_PREFIX}/rdp:xfce4-k8stools-${SERVICE_VERSION}

USER bigred
WORKDIR /home/bigred

COPY --chown=bigred:bigred --chmod=600 kube/config /home/bigred/.kube/config.tmp
COPY --chown=bigred:bigred --chmod=0755 bin/k8sadm-entry.sh /usr/local/bin/k8sadm-entry.sh

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/usr/local/bin/k8sadm-entry.sh"]
