# Multus CNI

![type: application](https://img.shields.io/badge/type-application-informational?style=flat-square) ![kube version: >=1.12.0-0](https://img.shields.io/badge/kube%20version->=1.12.0--0-informational?style=flat-square)

A Helm chart for Multus CNI - Meta CNI plugin for attaching multiple network interfaces to pods.

**Homepage:** <https://github.com/k8snetworkplumbingwg/multus-cni>

## TL;DR;

```bash
# Install Multus
helm install my-multus ./stable/multus --namespace kube-system
```

## Introduction

Multus CNI is a container network interface (CNI) plugin for Kubernetes that enables attaching multiple network interfaces to pods. It acts as a "meta" plugin that can call other CNI plugins to configure additional network interfaces.

## Prerequisites

- Kubernetes 1.12+
- Helm 3.0+
- A primary CNI plugin (e.g., Calico, Cilium) already installed
- **Note:** CRDs are automatically installed by Helm Chart API v2

## Installing the Chart

### Step 1: Install Multus
```bash
helm install my-multus ./stable/multus --namespace kube-system
```

### Step 2: Configure Primary CNI Detection
Set the readiness indicator file for your primary CNI:

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
| `imagePullSecrets` | Image pull secrets | `[]` |
| `serviceAccount.create` | Create service account | `true` |
| `serviceAccount.name` | Service account name | `multus` |
| `serviceAccount.annotations` | Service account annotations | `{}` |
| `rbac.create` | Create RBAC resources | `true` |
| `podSecurityContext.privileged` | Pod security context | `true` |
| `securityContext.privileged` | Container security context | `true` |
| `securityContext.capabilities.add` | Additional capabilities | `[NET_ADMIN, SYS_ADMIN]` |
| `priorityClassName` | Priority class name | `system-node-critical` |
| `hostNetwork` | Enable host network for pods | `true` |
| `hostPID` | Enable host PID namespace for pods | `true` |
| `terminationGracePeriodSeconds` | Grace period for pod termination | `10` |
| `updateStrategy.type` | Update strategy | `RollingUpdate` |
| `updateStrategy.rollingUpdate.maxUnavailable` | Max unavailable pods | `1` |
| `tolerations` | Pod tolerations | `[{"operator": "Exists", "effect": "NoSchedule"}, {"operator": "Exists", "effect": "NoExecute"}]` |
| `nodeSelector` | Node selector | `{}` |
| `affinity` | Pod affinity | `{}` |
| `podAnnotations` | Pod annotations | `{}` |
| `podLabels` | Pod labels | `{}` |
| `resources.limits.cpu` | CPU limit | `100m` |
| `resources.limits.memory` | Memory limit | `128Mi` |
| `resources.requests.cpu` | CPU request | `100m` |
| `resources.requests.memory` | Memory request | `128Mi` |
| `daemonConfig.chrootDir` | Chroot directory | `/hostroot` |
| `daemonConfig.cniVersion` | CNI version | `0.3.1` |
| `daemonConfig.logLevel` | Log level | `verbose` |
| `daemonConfig.logToStderr` | Log to stderr | `true` |
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

### CRD Verification
Check if CRDs are installed:
```bash
kubectl get crd network-attachment-definitions.k8s.cni.cncf.io
```

### Primary CNI Not Detected
Ensure `daemonConfig.readinessIndicatorFile` is set to the correct socket path for your primary CNI.

### Pod Security Policy Errors
This chart requires privileged containers. Ensure your cluster's Pod Security Policy or Pod Security Standards allow privileged containers for the kube-system namespace.

## License

Copyright 2024 Nutanix. All rights reserved.
SPDX-License-Identifier: Apache-2.0
