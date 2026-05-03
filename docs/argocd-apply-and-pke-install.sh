sudo k3s kubectl create namespace argocd
sudo k3s kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --server-side

sudo k3s kubectl apply -f app-cert-manager.yaml
sudo k3s kubectl wait --for=jsonpath='{.status.sync.status}'=Synced application/cert-manager -n argocd --timeout=300s
sudo k3s kubectl wait --for=jsonpath='{.status.health.status}'=Healthy application/cert-manager -n argocd --timeout=300s

sudo k3s kubectl apply -f app-cluster-api-operator.yaml
sudo k3s kubectl wait --for=jsonpath='{.status.sync.status}'=Synced application/cluster-api-operator -n argocd --timeout=300s
sudo k3s kubectl wait --for=jsonpath='{.status.health.status}'=Healthy application/cluster-api-operator -n argocd --timeout=300s
# wait until the crds are ready
sudo k3s kubectl wait --for=condition=Ready coreprovider/cluster-api -n capi-system --timeout=300s
sudo k3s kubectl wait --for=condition=Ready bootstrapprovider/kubeadm -n kubeadm-bootstrap-system --timeout=300s
sudo k3s kubectl wait --for=condition=Ready controlplaneprovider/kubeadm -n kubeadm-control-plane-system --timeout=300s
sudo k3s kubectl wait --for=condition=Ready infrastructureprovider/proxmox -n proxmox-infrastructure-system --timeout=300s
sudo k3s kubectl wait --for=condition=Ready ipamprovider/in-cluster -n in-cluster-ipam-system --timeout=300s
sudo k3s kubectl wait --for=condition=Ready addonprovider/helm -n helm-addon-system --timeout=300s

sudo k3s kubectl apply -f app-proxmox-kubernetes-engine.yaml
