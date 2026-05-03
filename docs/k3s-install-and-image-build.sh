# install k3s-Kubernetes with k3sup
curl -sLS https://get.k3sup.dev | sh
sudo cp k3sup /usr/local/bin/k3sup
k3sup install --local --k3s-version v1.34.7+k3s1
# wait until its ready
sudo k3s kubectl wait --for=condition=Ready node/management-vm --timeout=60s
# create a namespace for the build
sudo k3s kubectl create namespace proxmox-build-infrastructure-system
# apply secret & job
sudo k3s kubectl apply -f build-secret.yaml
sudo k3s kubectl apply -f job.yaml
# start the build
sudo k3s kubectl create job build-image --from cj/proxmox-template-builder -n proxmox-build-infrastructure-system 
# wait until the job is copmleted
sudo k3s kubectl wait --for=condition=complete job/build-image -n proxmox-build-infrastructure-system -timeout=30m