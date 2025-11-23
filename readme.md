# Proxmox Kubernetes Engine (PKE)
PKE (Proxmox Kubernetes Engine) is a solution for automatically deploying and managing high available Kubernetes clusters directly on Proxmox VE environments. It is designed for homelabbers and small and medium enterprises (KMUs/SMEs) as a simpler yet flexible alternative to OpenShift, Tanzu, or Rancher. It does not require SSH access or modifications to your Proxmox VE nodes.

![Image description](https://i.ibb.co/6JVF7Z23/background-drawio-2.png)

## Quick-Links
* [Quick Start](./docs/quick-start.md)
* [Initial blogpost](https://dev.to/3deep5me/from-zero-to-scale-kubernetes-on-proxmox-the-scaling-autopilot-method-1l64)

## Features
- Native Proxmox storage integration with [proxmox-csi](https://github.com/sergelogvinov/proxmox-csi-plugin/tree/main)
- Load balancing with [kube-vip](https://github.com/kube-vip/kube-vip)
- Networking with [Cilium](https://github.com/cilium/cilium)
- Fully API-driven

No code is written - if a feature is needed, I prefer to contribute upstream.

## Architecutre
![Image description](https://dev-to-uploads.s3.amazonaws.com/uploads/articles/htlnxjzkz6m11w5rlrsv.png)

The architecture is completely based on Cluster API. For details, refer to the [Cluster API Documentation](https://cluster-api.sigs.k8s.io/user/concepts). In the Quick Start, K3s is used as the management VM. Please refer to the [Quick Start](./docs/quick-start.md) for more information.

## Why Proxmox and Kubernetes Cluster-API?

### Proxmox
Proxmox, developed in Vienna, is widely known in the open-source and home-lab communities.
It gained a huge boost in small to medium-scale private clouds after VMware's new pricing model alienated its customers.
It's a simple yet powerful open-source hypervisor based on KVM, and it's been the core of my home lab for nearly a decade (I've been using it since PVE 4).

### Kubernetes Cluster-API
While Cluster API might be less known in the home-lab community, it's highly valued in enterprises and by Kubernetes administrators and enthusiasts. 

Cluster API is a project under the Cloud Native Computing Foundation (CNCF), strongly supported by the Kubernetes community and various vendors, including VMware, Apple, and NVIDIA. This project offers a unified way to create and manage Kubernetes clusters across different "providers," such as Proxmox or VMware. For instance, VMware heavily leverages Cluster API in its commercial product, Tanzu.

Cluster API currently boasts over 30 infrastructure providers, with Proxmox being just one of them. In short, Cluster API provides a unified API and method for creating production-ready Kubernetes clusters across numerous providers. It has become, at least for me, the de facto standard for multi-cloud and on-premises Kubernetes deployments.

In my opinion, they are a perfect match for a modern, open-source, Kubernetes-based private cloud.

## Roadmap
- [ ] Web-UI with [cyclops](https://github.com/cyclops-ui/cyclops)
- [ ] Migrate to v1beta2 cluster-api

## Also in this Area
- [Cozystack PaaS-hosted](https://cozystack.io/docs/operations/configuration/bundles/#paas-hosted): Convert your Kubernetes cluster into a full cloud experience
