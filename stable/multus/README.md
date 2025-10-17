# Multus CNI

![type: application](https://img.shields.io/badge/type-application-informational?style=flat-square) ![kube version: >=1.12.0-0](https://img.shields.io/badge/kube%20version->=1.12.0--0-informational?style=flat-square)

A Helm chart for Multus CNI - Meta CNI plugin for attaching multiple network interfaces to pods.

**Homepage:** <https://github.com/k8snetworkplumbingwg/multus-cni>

## TL;DR;

```bash
# Install CRDs first (required)
kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset-thick.yml

# Install Multus
helm install my-multus ./stable/multus --namespace kube-system
```

## Introduction

Multus CNI is a container network interface (CNI) plugin for Kubernetes that enables attaching multiple network interfaces to pods. It acts as a "meta" plugin that can call other CNI plugins to configure additional network interfaces.

## Prerequisites

- Kubernetes 1.12+
- Helm 3.0+
- A primary CNI plugin (e.g., Calico, Cilium) already installed
- **CRDs must be installed separately** (see Installation section)

## Installing the Chart

### Step 1: Install CRDs (Required)

```bash
# Option 1: Install from official source
kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset-thick.yml

# Option 2: Install from chart's CRD files
kubectl apply -f ./stable/multus/crds/crd.yaml
```

### Step 2: Install Multus

```bash
helm install my-multus ./stable/multus --namespace kube-system
```

### Step 3: Configure Primary CNI Detection

Configure the readiness indicator file for your primary CNI:

```bash
# For Cilium
helm upgrade my-multus ./stable/multus --set daemonConfig.readinessIndicatorFile="/run/cilium/cilium.sock"

# For Calico
helm upgrade my-multus ./stable/multus --set daemonConfig.readinessIndicatorFile="/run/calico/calico.sock"
```

## Uninstalling the Chart

```bash
helm delete my-multus
# Note: CRDs are not automatically removed
```

## Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `image.repository` | Multus image repository | `ghcr.io/k8snetworkplumbingwg/multus-cni` |
| `image.tag` | Multus image tag | `v4.2.2-thick` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `serviceAccount.create` | Create service account | `true` |
| `serviceAccount.name` | Service account name | `multus` |
| `rbac.create` | Create RBAC resources | `true` |
| `podSecurityContext.privileged` | Pod security context | `true` |
| `securityContext.privileged` | Container security context | `true` |
| `securityContext.capabilities.add` | Additional capabilities | `[NET_ADMIN, SYS_ADMIN]` |
| `priorityClassName` | Priority class name | `system-node-critical` |
| `updateStrategy.type` | Update strategy | `RollingUpdate` |
| `updateStrategy.rollingUpdate.maxUnavailable` | Max unavailable pods | `1` |
| `resources.limits.cpu` | CPU limit | `100m` |
| `resources.limits.memory` | Memory limit | `128Mi` |
| `resources.requests.cpu` | CPU request | `100m` |
| `resources.requests.memory` | Memory request | `128Mi` |
| `daemonConfig.logLevel` | Log level | `verbose` |
| `daemonConfig.cniVersion` | CNI version | `0.3.1` |
| `daemonConfig.readinessIndicatorFile` | Readiness indicator file | `""` (must be set) |
| `daemonConfig.cniConfigDir` | CNI config directory | `/host/etc/cni/net.d` |
| `daemonConfig.multusAutoconfigDir` | Multus autoconfig directory | `/host/etc/cni/net.d` |
| `daemonConfig.multusConfigFile` | Multus config file | `auto` |
| `daemonConfig.socketDir` | Socket directory | `/host/run/multus/` |

## Dynamic Configuration

This chart supports dynamic configuration based on the primary CNI provider:

### For Cilium as Primary CNI:
```yaml
daemonConfig:
  readinessIndicatorFile: "/run/cilium/cilium.sock"
```

### For Calico as Primary CNI:
```yaml
daemonConfig:
  readinessIndicatorFile: "/run/calico/calico.sock"
```

## Usage

Multus works by delegating to other CNI plugins. After installation, create NetworkAttachmentDefinition resources to define additional networks:

```yaml
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: macvlan-conf
  namespace: default
spec:
  config: '{
    "cniVersion": "0.3.1",
    "type": "macvlan",
    "master": "eth0",
    "mode": "bridge",
    "ipam": {
      "type": "host-local",
      "subnet": "192.168.1.0/24"
    }
  }'
```

Then annotate your pods to use additional networks:
```yaml
metadata:
  annotations:
    k8s.v1.cni.cncf.io/networks: macvlan-conf
```

## Troubleshooting

### CRD Not Found Error
If you see errors about NetworkAttachmentDefinition not being found, ensure CRDs are installed:
```bash
kubectl get crd network-attachment-definitions.k8s.cni.cncf.io
```

### Primary CNI Not Detected
Ensure `daemonConfig.readinessIndicatorFile` is set to the correct socket path for your primary CNI.

## License

Copyright 2024 Nutanix. All rights reserved.
SPDX-License-Identifier: Apache-2.0
