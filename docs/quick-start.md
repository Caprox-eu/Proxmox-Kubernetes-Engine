### Proxmox Kubernete Engine - "Quick-Start"

The Quick Start will walk you through these steps.

1. Create the Management VM as our pivotal point.
2. Create a Kubernetes VM Template for our Kubernetes Clusters.
3. Initialize Cluster API & Configure the "Proxmox-Kubernetes-Engine"
4. Create our first Workload Cluster.

In my example, the Management VM and Kubernetes clusters will all reside on a single Proxmox host within one network that utilizes DHCP. DHCP is a requirement, this Quick Start also works for a Proxmox Cluster. 

## Create the Management VM with k3sup

**Disclaimer**: All the steps shown here are for home-lab purposes only and **should not be used for a production or even development environment**. This guide is merely a starting point. If you're looking for a more production-ready setup, feel free to reach out to me.

### Create a New VM for Our Management VM

We need a simple Linux VM for our **Management VM** with **30 GiB of disk space** and at least **4 GiB of RAM**.

For Proxmox beginners, I recommend [this great guide](https://support.us.ovhcloud.com/hc/en-us/articles/360010916620-How-to-Create-a-VM-in-Proxmox-VE). You'll also need an ISO image, which you can download [here](https://ubuntu.com/download/server/thank-you?version=24.04.2&architecture=amd64&lts=true) from the official Ubuntu website.

Of course, you can also use other methods such as Terraform, cloud-init or cloning an existing Linux VM or template.

Once you've logged into your new VM, we can proceed.

### Install Kubernetes (K3s) on Our New VM

Cluster API is Kubernetes-exclusive, meaning it itself relies on Kubernetes to operate. Because of this, we need Kubernetes on our Management VM. In this guide, we'll use **K3s** for that. K3s is a Kubernetes distribution from Rancher that is now fully community-driven and under the CNCF. It's a popular Kubernetes distro for small to mid-sized clusters.

To install K3s, we'll use **`k3sup`** - a really simple CLI tool that allows you to create a K3s Kubernetes cluster within seconds on any Linux VM. The following commands will download `k3sup` and then create a simple cluster.

```bash
# install k3s-Kubernetes with k3sup
curl -sLS https://get.k3sup.dev | sh
sudo cp k3sup /usr/local/bin/k3sup
k3sup install --local --k3s-version v1.34.1+k3s1
```
You can test if the cluster is working with `sudo k3s kubectl get nodes`. It should show something like this:
```bash
sudo k3s kubectl get nodes
NAME        STATUS   ROLES                  AGE     VERSION
localhost   Ready    control-plane,master   6m30s   v1.34.1+k3s1
```
Congratulations! You've successfully set up a simple single-node Kubernetes cluster. This cluster will serve as our Cluster API Management VM.

## Creating Your Kubernetes VM Template

Every Kubernetes cluster typically starts with a machine template, most often a **VM template**. This template is where all Kubernetes components are configured and downloaded. For Cluster API, we need VM templates that already include essential Kubernetes packages like the API server and the container runtime.

We'll achieve this with the help of the excellent [Kubernetes Image Builder](https://github.com/kubernetes-sigs/image-builder/tree/main) project. While it sounds fancy, it's essentially **Packer and Ansible** cleverly glued together to automate the image creation process. But as promised, you don't need to touch Ansible or Packer at all.

### Create an API Token and a Secret with the Values

To get started, we need to create API access to our Proxmox Datacenter. You might wonder why. The image builder constructs the image directly on your Proxmox node, so it requires access to start a VM and later convert it into a template.

To begin, open a shell on your Proxmox node. You can do this by clicking on your Proxmox node in the interface and selecting "Shell"; a command-line interface will then open directly in your browser. Once the shell is open, execute the following commands:

```bash
pveum user add caprox@pve
pveum aclmod / -user caprox@pve -role PVEAdmin
pveum user token add caprox@pve capi -privsep 0
```
After that you should get all relevant information.
```bash
root@node01:~# pveum user token add caprox@pve capi -privsep 0
┌──────────────┬──────────────────────────────────────┐
│ key          │ value                                │
╞══════════════╪══════════════════════════════════════╡
│ full-tokenid │ caprox@pve!capi                      │
├──────────────┼──────────────────────────────────────┤
│ info         │ {"privsep":"0"}                      │
├──────────────┼──────────────────────────────────────┤
│ value        │ 6e59df15-a2c9-4dc5-b293-367772950c68 │
└──────────────┴──────────────────────────────────────┘
```
We will also use our Management VM to coordinate the VM Template Builds. For that we will use the Kubernetes Job Resource and a Kubernetes Secret to pass the API-Key and some configuration.

First let us create the Secret with values we got from above.
You only need to change the first four Proxmox-Vars.
```yaml
# secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: proxmox-image-build-config
  namespace: proxmox-build-infrastructure-system
type: Opaque
stringData:
  PROXMOX_URL: "https://your-proxmox-adress:8006/api2/json"
  PROXMOX_USERNAME: "full-tokenid"
  PROXMOX_TOKEN: "value"
  PROXMOX_NODE: "your proxmox node name"
  PROXMOX_ISO_POOL: "local" #this should be fine for the most users
  PROXMOX_BRIDGE: "vmbr0" #this should be fine for the most users
  PROXMOX_STORAGE_POOL: "local" #this should be fine for the most users
  PACKER_FLAGS: >-
   --var memory=4096 
   --var kubernetes_rpm_version=1.33.1
   --var kubernetes_semver=v1.33.1 
   --var kubernetes_series=v1.33 
   --var kubernetes_deb_version=1.33.1-1.1
```
Configure needed values and save the File.

Example on how to use ubuntu server
```yaml
  --var iso_url=https://releases.ubuntu.com/noble/ubuntu-24.04.3-live-server-amd64.iso
  --var iso_checksum=c3514bf0056180d09376462a7a1b4f213c1d6e8ea67fae5c25099c6fd3d8274b
```

If the builder complains about the storage for lvm-thin add this to the packer flags.
```yaml
--var disk_format=raw
```


Now we need also a Job which creates the Image. A Job is a Kubernetes Pod which is only executed once with a finite life - until the Job successfully complete. It uses Image-Builder Docker-Image with the required configuration to build Kubernetes Proxmox VM-Templates. 
```yaml
# job.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: proxmox-template-builder
  namespace: proxmox-build-infrastructure-system
spec:
  schedule: "* * * * *"
  suspend: true 
  jobTemplate:
    spec:
      template:
        spec:
          hostNetwork: true
          restartPolicy: OnFailure
          containers:
          - name: image-builder
            image: registry.k8s.io/scl-image-builder/cluster-node-image-builder-amd64:v0.1.45
            envFrom:
            - secretRef:
                name: proxmox-image-build-config
            args:
            - build-proxmox-ubuntu-2404
            env:
            # help for slow nodes
              - name: ANSIBLE_TIMEOUT
                value: "60"
```
Just copy and save the file.

### Start the Build-Job and create a Kubernetes Image

Now you should have two file one Secret and one (Cron)-Job, the Cron-Job has the benefit of easier executing if we need new image or even do scheduled automatic builds. Now its build time!

```bash
# create a namespace for the build
sudo k3s kubectl create namespace proxmox-build-infrastructure-system
# apply secret & job
sudo k3s kubectl apply -f secret.yaml
sudo k3s kubectl apply -f job.yaml
# start the build
sudo k3s kubectl create job build-image --from cj/proxmox-template-builder -n proxmox-build-infrastructure-system 
```

To Monitor the current state we can look at the Logs of the Builder-Pod. For that we need the name and the `kubectl logs` command.
```bash
sudo k3s kubectl get pods -n proxmox-build-infrastructure-system
NAME                READY   STATUS    RESTARTS   AGE
build-image-tdv78   1/1     Running   0          97s
sudo k3s kubectl logs -f -n proxmox-build-infrastructure-system build-image-tdv78
proxmox-iso.ubuntu-2204: output will be in this color.
==> proxmox-iso.ubuntu-2204: Retrieving ISO
...
```
You should see a new VM pop-up in your Proxmox UI. This is often the trickiest part of the guide. Sometimes it can take a long time, or the job might even require multiple attempts. Kubernetes will automatically restart the job if the build fails, so you can just relax and let it do its thing. In my experience, it occasionally took over 30 minutes to create the VM template.

Please ensure that you have DHCP configured in your network. If you encounter any issues, feel free to leave a comment below; I'm happy to help! Sometimes a Proxmox reboot also helps.

If you're lucky, you should see a new template in the UI after a few minutes.![Image description](https://dev-to-uploads.s3.amazonaws.com/uploads/articles/ebymhlsjwkqa2o49bhek.png)

And thats it - you completed the "most complicated" part!

## Initialize Cluster-API
In the next step, we'll configure Cluster-API to our needs. I prefer to avoid keeping files, especially complex ones, directly on my PC. For this reason, we'll use **ArgoCD** with a **GitOps workflow** to install Cluster-API. New to GitOps and ArgoCD? Don't worry, it's straightforward!

### Install ArgoCD and get Cluster API
ArgoCD will retrieve the YAML configurations for the various Cluster-API components. You can install ArgoCD using these two commands:
```bash
sudo k3s kubectl create namespace argocd
sudo k3s kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```
You can check the status of argocd with this command `sudo k3s kubectl get pods -n argocd` if all pods are running you are ready for the next step.

We will install these Cluster-API components as ArgoCD Applications. An ArgoCD Application is similar to something you might know from your Google Play Store or Apple App Store – it's a packaged application or set of applications. Just as you download and install an app on your phone, ArgoCD manages the deployment and lifecycle of these Cluster-API components onto your Kubernetes clusters.
* [Cluster-API Operator](https://github.com/kubernetes-sigs/cluster-api-operator)
    * The operator is responsible for installing Cluster-API and configuring it for Proxmox.
* [Cert-Manager](https://cert-manager.io/).  
    * Cert-Manager is utilized by Cluster-API to automatically generate and manage certificates required for the Kubernetes clusters.
* [Proxmox-Kubernetes-Engine](https://github.com/Caprox-eu/Proxmox-Kubernetes-Engine)
    * This application includes my opinionated ClusterClass, which has been designed with the needs of home labs and Small and Medium-sized Businesses (SMBs) in mind. A ClusterClass acts as a customizable template, significantly simplifying the process of creating and managing Kubernetes clusters.

```yaml
# app-cert-manager.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cluster-api-operator-cert-manager
  namespace: argocd 
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  destination:
    namespace: capi-operator-system
    server: https://kubernetes.default.svc
  project: default
  source:
    repoURL: https://charts.jetstack.io
    targetRevision: 1.18.2
    chart: cert-manager
    helm:
      values: |
        installCRDs: true
  syncPolicy:
    syncOptions:
    - CreateNamespace=true
    - ServerSideApply=true
    automated: 
      prune: true
      selfHeal: true
```
```yaml
# app-cluster-api.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cluster-api-operator-main
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  destination:
    namespace: capi-operator-system
    server: https://kubernetes.default.svc
  project: default
  source:
    repoURL: https://kubernetes-sigs.github.io/cluster-api-operator
    targetRevision: 0.23.0
    chart: cluster-api-operator
    helm:
      values: |
        manager:
          featureGates:
            proxmox:
              ClusterTopology: true
            core:
              ClusterTopology: true
            kubeadm:
              ClusterTopology: true
        core:
          cluster-api:
            enabled: true
            version: v1.10.6
        bootstrap:
          kubeadm: 
            enabled: true
            version: v1.10.6
        controlPlane: 
          kubeadm: 
            enabled: true
            version: v1.10.6
        infrastructure: 
          proxmox:
            enabled: true
            version: v0.7.4
        ipam:
          in-cluster:
            enabled: true
            version: v1.0.3
        addon:
          helm: 
            enabled: true
            version: v0.3.2
  syncPolicy:
    syncOptions:
    - CreateNamespace=true
    - ServerSideApply=true
    automated: 
      prune: true
      selfHeal: true
```
```yaml
# app-proxmox-kubernetes-engine.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: proxmox-kubernetes-engine
  namespace: argocd 
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  destination:
    namespace: capi-operator-system
    server: https://kubernetes.default.svc
  project: default
  source:
    repoURL: https://github.com/Caprox-eu/Proxmox-Kubernetes-Engine.git
    targetRevision: main
    path: manifests/clusterclass-cilium-with-shared-ippool/base
  syncPolicy:
    syncOptions:
    - CreateNamespace=true
    - ServerSideApply=true
    automated: 
      prune: true
      selfHeal: true
  ignoreDifferences:
    - group: cluster.x-k8s.io
      kind: ClusterClass
      jsonPointers:
        - /spec
```
Save these files and apply them one by one. This sequential application is necessary because the applications depend on each other, and we need to ensure each one is ready before proceeding to the next.

Lets start with the Cert-Manager.
```bash
sudo k3s kubectl apply -f app-cert-manager.yaml
```
Wait until the App is Heathly and synced.
```bash
sudo k3s kubectl get apps -A
NAME                                 SYNC STATUS   HEALTH STATUS
cluster-api-operator-cert-manager    Synced        Healthy
...
```
Then go on with Cluster-API.
```bash
sudo k3s kubectl apply -f app-cluster-api.yaml
```
Wait until the App is Heathly and synced.
```bash
sudo k3s kubectl get apps -A
NAME                                 SYNC STATUS   HEALTH STATUS
cluster-api-operator-cert-manager    Synced        Healthy
cluster-api-operator-main            Synced        Healthy
...
```
Then with the caprox-engine.
```bash
sudo k3s kubectl apply -f app-proxmox-kubernetes-engine.yaml
```
Wait until the App is Heathly and synced.
```bash
sudo k3s kubectl get apps -A
NAME                                 SYNC STATUS   HEALTH STATUS
cluster-api-operator-cert-manager    Synced        Healthy
cluster-api-operator-main            Synced        Healthy
proxmox-kubernetes-engine            Synced        Healthy
...
```
Nice! Now we need to configure cluster-api to our specific environment.

### Connect Cluster-API to Proxmox
Cluster-API needs access to your Proxmox cluster to create VMs for Kubernetes clusters. For a homelab setup, we can simply reuse the Proxmox credentials you created in the "Create an API Token and Create a Secret with the Values" step.

Create this Secret with the exact same structure, configure it for your environment, then save and apply it.

```yaml
# secret-capmox.yaml
apiVersion: v1
stringData:
  secret: "6e59df15-a2c9-4dc5-b293-367772950c68"
  token: "caprox@pve!capi"
  # note: only the host - not the api-path
  url: "https://192.168.2.142:8006/"
kind: Secret
metadata:
  name: capmox-manager-credentials
  namespace: proxmox-infrastructure-system
``` 

Create the secret.
```bash
sudo k3s kubectl apply -f secret-capmox.yaml
```
Because we are overwriting the default secret we need to trigger a restart of the proxmox-provider to read the new secret.
```bash
sudo k3s kubectl rollout restart deploy capmox-controller-manager -n proxmox-infrastructure-system
```

### Connect you future Clusters to Proxmox-Storage
Your Clusters later needs access to Proxmox to create new persistent Volumes / Proxmox Disks. For that we need to create a seperate Secret which will be copied automatiaclly in newly created Clusters. For a homelab setup, we can simply reuse the Proxmox credentials you created in the "Create an API Token and Create a Secret with the Values" step.

Create this Secret with the exact same structure, configure it for your environment, then save and apply it.

```yaml
# secret-proxmox-cluster-storage.yaml
apiVersion: v1
stringData:
  proxmox-credentials: |-
    apiVersion: v1
    kind: Secret
    metadata:
      name: proxmox-credentials
      namespace: kube-system
    stringData:
      # change this
      token_id: "xxx@pve!capi"
      token_secret: "xxx-xxx-xxx-xxx-xxx"
    ---
    apiVersion: v1
    stringData:
      config.yaml: |-
        clusters:
        - insecure: true
          region: Datacenter
          token_id_file: /var/run/secrets/proxmox/token_id
          token_secret_file: /var/run/secrets/proxmox/token_secret
          # change this
          url: https://192.168.2.142:8006/api2/json
    features:
      provider: capmox
    kind: Secret
    metadata:
      name: csi-proxmox-csi-plugin
      namespace: kube-system
    ---
    apiVersion: v1
    stringData:
      config.yaml: |-
        clusters:
        - insecure: true
          region: Datacenter
          token_id_file: /var/run/secrets/proxmox/token_id
          token_secret_file: /var/run/secrets/proxmox/token_secret
          # change this
          url: https://192.168.2.142:8006/api2/json
    features:
      provider: capmox
    kind: Secret
    metadata:
      name: ccm-proxmox-cloud-controller-manager
      namespace: kube-system
    type: Opaque
kind: Secret
metadata:
  name: proxmox-credentials
  namespace: caprox-kubernetes-engine
  annotations:
    docs: this is the secret which will be used in the workload cluster to attach and detach volumes
type: addons.cluster.x-k8s.io/resource-set
```
Create the secret.
```bash
sudo k3s kubectl apply -f secret-proxmox-cluster-storage.yaml
```

### Configure IP Range for the Cluster-API Caprox Kubernetes Engine
The Virtual Machines (VMs) provisioned by Proxmox/Cluster-API will require IP addresses. Currently, DHCP support is [not available](https://github.com/ionos-cloud/cluster-api-provider-proxmox/issues/29). However, we can specify an IP pool for our Kubernetes VMs. In my setup, I've disabled DHCP for a range of IPs within my FritzBox. (Note: It's recommended to disable DHCP for more IPs than you initially anticipate needing – more on this later.)

Copy this file, configure it for your network, then save and apply it.

```yaml
# ip-pool.yaml
apiVersion: ipam.cluster.x-k8s.io/v1alpha2
kind: InClusterIPPool
metadata:
  name: clusterclass-ipv4
  namespace: caprox-kubernetes-engine
spec:
  # Change the IP range to match your needs
  # These IPs will be used for the Kubernetes nodes
  # Also configure your network prefix and gateway accordingly
  addresses:
  - 192.168.2.150-192.168.2.199
  gateway: 192.168.2.1
  prefix: 24
```
```bash
sudo k3s kubectl apply -f ip-pool.yaml
```

That's it! We've successfully installed ArgoCD on our Management VM, used ArgoCD to install Cluster-API, and configured Cluster-API for our environment. Now we're finally ready to create our first multi-node Kubernetes cluster!

## Create our first Workload Cluster
As always everthing is a file - same is true for a Kubernetes Cluster in Cluster-API. So yeah we will create a Kubernetes Cluster from Cluster YAML. The file will be later proccesed by Cluster-API within our Management VM.

### The Cluster Resource
A cluster configuration which is compatible with our setup could look like this.
```yaml
# cluster.yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  labels:
    # mandatory for functional cluster
    caprox.eu/cni: cilium-v1.17.4
    caprox.eu/ccm: "true"
    caprox.eu/inject-proxmox-credentials: "true"
    # optional
    caprox.eu/csi: "true"
    caprox.eu/service-lb: "true"
  name: manuels-k8s-cluster
  namespace: caprox-kubernetes-engine 
spec:
  topology:
    class: proxmox-clusterclass-cilium-v0.1.0
    version: 1.33.1
    controlPlane:
      replicas: 1
    workers:
      machineDeployments:
      - class: proxmox-worker
        name: proxmox-worker-pool
        replicas: 1
    variables:
    - name: cloneSpec
      value:
        sshAuthorizedKeys:
          - "ssh-ed25519 replace-with-your-ssh-key-and-ssh-to-node-ip-as root"
        vmTemplate:
          sourceNode: node01
          templateID: 114
        
        #Example of if you want to modify node resources
        #machineSpec:
        #  controlPlane:
        #    numCores: 2
        #    numSockets: 1
        #    memoryMiB: 4096
        #  workerNode:
        #    numCores: 6
        #    numSockets: 1
        #    memoryMiB: 6144
        #    disks:
        #      bootVolume:
        #        disk: scsi0
        #        sizeGb: 80
    - name: controlPlaneEndpoint
      value:
        host: 192.168.2.201
```

The fields you **must** change are:

* **`vmTemplate`**
    * **`sourceNode`**: Set this to the name of the Proxmox node where your VM template is located.
    * **`templateID`**: This is the ID of your Kubernetes template. You can find it in the Proxmox UI, listed as the number next to the template name.

* **`controlPlaneEndpoint`**:
    * This IP address will be used to access your Kubernetes cluster.
    * Ensure it's outside your defined IP pool range.
    * This is a floating IP, shared among different nodes. This ensures your cluster remains reachable even during node failures or maintenance, as long as at least one node is available.

The fields you **can** change are:

* **`controlplane.replicas`**:
    * This specifies the number of VMs for your control plane (master) nodes. These nodes host Kubernetes control plane components like the Kubernetes API and etcd (the Kubernetes database).
    * Set this to `1` for a non-HA (High Availability) setup, or `3` or `5` for an HA setup.

* **`workers.replicas`**:
    * This determines the number of VMs that will run your workloads.
    * Set this to at least `1`.

* **`metadata.name`**:
    * This is the name of your Kubernetes cluster.

For more configuration options, including memory and CPU settings for your VMs, refer to the available **variables** [here](https://github.com/3deep5me/kubernetes-gitops/blob/cluster-api-action/k3s-mgmt-proxmox/manifest/capmox-setup/cilium-clusterclass-with-shared-ippool/base/variables/clonespec.yaml).

After you've set the required fields, remember to save the file.

### Scaling and New Clusters

If you want to **scale out** your current cluster, simply adjust the **node replica counts** in your configuration file. Then, reapply the changes using `kubectl apply -f cluster.yaml`.

To create an **additional cluster**, create a new file with a different **`metadata.name`** and set your desired node replica counts.

### Create the Workload Cluster and Retrieve the Kubeconfig

To create the cluster, we need to "send" our cluster configuration to our Management VM. This action will kick off the cluster creation process, which is often referred to as **reconciliation**. After the first control plane VM is created and started, we can retrieve the **kubeconfig** for our new cluster. The kubeconfig file contains all the necessary login information to access the created cluster.

```bash
# Create the Cluster
sudo k3s kubectl apply -f cluster.yaml

# Retrieve and save the kubeconfig
sudo k3s kubectl get secrets -n caprox-kubernetes-engine manuels-k8s-cluster-kubeconfig -o jsonpath='{.data.value}' | base64 --decode > kubeconfig.yaml

# Connect to the new cluster
export KUBECONFIG=./kubeconfig.yaml
```

You can verify the connection by listing the nodes in your new cluster:

```bash
# This command should now show your multiple nodes, depending on your configuration.
kubectl get nodes
```

```bash
kubectl get nodes
NAME                                            STATUS   ROLES           AGE     VERSION
manuels-k8s-cluster-control-plane-4z458-ghx2z   Ready    control-plane   11m     v1.33.1
manuels-k8s-cluster-worker-6vhjx-c2nv2-v4dbw    Ready    node            5m23s   v1.33.1
```

If you want to interact with the Management VM/Cluster API again, you'll need to unset the environment variable:

```bash
unset KUBECONFIG
```

Congratulations! You've successfully completed the whole process. You can now **dynamically create Kubernetes clusters in your Proxmox datacenter in an API-driven way.**

If you'd like a guide on how to update your existing cluster, please let me know in the comments!


### Troubleshooting

There are many reasons why cluster creation might fail. I've tried to address all common errors within the template and reduce the setup steps to make the process as lean as possible. All versions and dependencies are fixed. I've tested this guide on multiple Proxmox datacenters and also asked friends to test it, and it has been successful every time.

However, if you encounter problems, it's likely that you either missed a step or didn't follow the guide exactly as described. Please feel free to leave a comment if you struggle or don't understand any steps.