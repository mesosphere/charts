# istio-helm-cni

Helm chart for deploying Istio CNI plugin.

## Overview

This chart contains only the Istio CNI subchart, which includes:
- CNI DaemonSet
- CNI configuration

## Installation

```bash
helm install istio-cni . --namespace kube-system
```

## Version

- Chart Version: 1.23.6
- Istio Version: 1.23.6


