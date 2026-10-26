# kubeconfig
mkdir -p /root/.kube &>/dev/null
cp /etc/kubernetes/admin.conf /root/.kube/config &>/dev/null

# bash completion for kubectl
source /usr/share/bash-completion/bash_completion
source <(kubectl completion bash)
