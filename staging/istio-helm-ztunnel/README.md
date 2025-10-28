# istio-helm-ztunnel

Helm chart for deploying Istio ztunnel component for ambient mesh mode.

## Overview

This chart contains the Istio ztunnel subchart, which is required for enabling Istio ambient mesh mode. Ztunnel (zero-trust tunnel) is a per-node proxy that handles Layer 4 traffic in the ambient mesh.

## What is Ambient Mode?

Ambient mode is a sidecar-less data plane mode for Istio that moves the proxies out of the application pod and into the infrastructure. This reduces operational complexity and resource overhead while still providing security and observability features.

## Prerequisites

Before installing ztunnel, ensure that:
- Istio CNI is installed with ambient mode enabled
- Istio control plane (istiod) is configured for ambient mode

## Installation

```bash
helm install istio-ztunnel . --namespace istio-system
```

## Enabling Ambient Mode

To enable ambient mode for your workloads:

1. **Enable ztunnel** by setting `ztunnel.enabled: true` in your values
2. **Enable ambient in CNI** by setting `cni.ambient.enabled: true`
3. **Enable ambient in istiod** by setting `pilot.env.PILOT_ENABLE_AMBIENT: "true"`
4. **Label namespaces** with `istio.io/dataplane-mode: ambient` to enroll them

## Version

- Chart Version: 1.23.6
- Istio Version: 1.23.6

