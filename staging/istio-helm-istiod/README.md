# istio-helm-istiod

Helm chart for deploying Istio control plane (istiod) with monitoring and security.

## Overview

This chart contains the Istio istiod subchart plus:
- Istiod control plane
- Grafana dashboards
- Prometheus Operator ServiceMonitors
- Security (certificate management)

## Installation

```bash
helm install istio-helm-istiod . --namespace istio-system
```

## Version

- Chart Version: 1.23.6
- Istio Version: 1.23.6

