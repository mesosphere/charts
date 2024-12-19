# Container Object Storage Interface (COSI) Helm Chart

This Helm chart deploys the Kubernetes SIGs [Container Object Storage Interface (COSI)](https://github.com/kubernetes-sigs/container-object-storage-interface) components onto a Kubernetes cluster.

## Overview

COSI provides a standardized interface for object storage in Kubernetes, enabling dynamic provisioning and management of object storage buckets and access credentials.

This chart includes:
- COSI Controller
- Sidecar containers
- CRDs required for COSI

## Prerequisites

- Kubernetes 1.21 or newer
- Helm 3.5.0 or newer
- [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) installed and configured
- Permissions to install Custom Resource Definitions (CRDs)

## Installation

### Add the Helm Repository

```bash
helm repo add mesosphere-stable https://mesosphere.github.io/charts/stable
helm repo update
helm install cosi-release mesosphere-stable/cosi --create-namespace
```
