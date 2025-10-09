# Multus CNI

A Helm chart for Multus CNI - Meta CNI plugin for attaching multiple network interfaces to pods.

## Introduction

Multus CNI is a container network interface (CNI) plugin for Kubernetes that enables attaching multiple network interfaces to pods. It acts as a "meta" plugin that can call other CNI plugins to configure additional network interfaces.

## Prerequisites

- Kubernetes 1.12+
- Helm 3.0+
- A primary CNI plugin (e.g., Calico, Cilium) already installed

## Installing the Chart

To install the chart with the release name `my-multus`:

```bash
helm repo add mesosphere-staging https://mesosphere.github.io/charts/staging
helm repo update
helm install my-multus mesosphere-staging/multus
```

## Uninstalling the Chart

To uninstall/delete the `my-multus` deployment:

```bash
helm delete my-multus
```

## Configuration

The following table lists the configurable parameters and their default values.

| Parameter | Description | Default |
|-----------|-------------|---------|
| `image.repository` | Multus image repository | `ghcr.io/k8snetworkplumbingwg/multus-cni` |
| `image.tag` | Multus image tag | `v4.3.7` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `serviceAccount.create` | Create service account | `true` |
| `serviceAccount.name` | Service account name | `multus` |
| `rbac.create` | Create RBAC resources | `true` |
| `resources.limits.cpu` | CPU limit | `100m` |
| `resources.limits.memory` | Memory limit | `128Mi` |
| `resources.requests.cpu` | CPU request | `100m` |
| `resources.requests.memory` | Memory request | `128Mi` |
| `daemonConfig.logLevel` | Log level | `verbose` |
| `daemonConfig.cniVersion` | CNI version | `0.3.1` |
| `primaryCNI.provider` | Primary CNI provider | `cilium` |
| `primaryCNI.socketPath` | Primary CNI socket path | `/run/cilium/cilium.sock` |
| `daemonConfig.readinessIndicatorFile` | Readiness indicator file | `/run/cilium/cilium.sock` |

## Dynamic Configuration

This chart supports dynamic configuration based on the primary CNI provider:

### For Cilium as Primary CNI:
```yaml
primaryCNI:
  provider: "cilium"
  socketPath: "/run/cilium/cilium.sock"
daemonConfig:
  readinessIndicatorFile: "/run/cilium/cilium.sock"
cniConfig:
  delegates: |
    [
      {
        "cniVersion": "0.3.1",
        "name": "cilium",
        "type": "cilium-cni"
      }
    ]
```

### For Calico as Primary CNI:
```yaml
primaryCNI:
  provider: "calico"
  socketPath: "/run/calico/calico.sock"
daemonConfig:
  readinessIndicatorFile: "/run/calico/calico.sock"
cniConfig:
  delegates: |
    [
      {
        "cniVersion": "0.3.1",
        "name": "calico",
        "type": "calico"
      }
    ]
```

## Usage

Multus works by delegating to other CNI plugins. Configure the `cniConfig.delegates` section to specify which CNI plugins Multus should delegate to.

## License

Copyright 2024 Nutanix. All rights reserved.
SPDX-License-Identifier: Apache-2.0
