# proxmox-kubernetes-cluster

A Helm chart for deploying a Kubernetes Cluster on Proxmox VE using Proxmox Kubernetes Engine (PKE).

This chart simplifies the deployment of the Cluster object, including configurable versions, node counts, features, and essential networking (Control Plane Endpoint).

## Prerequisites

* Kubernetes (for installing the chart)
* A running instance of the Proxmox Kubernetes Engine

## Installation

To install the chart with the release name `my-proxmox-k8s-cluster`:

```bash
helm install my-proxmox-k8s-cluster proxmox-kubernetes-cluster \
    --set controlPlane.endpoint="192.168.1.100" \