# istio-helm-gateway

Helm chart for deploying Istio ingress gateway.

## Overview

This chart contains only the Istio gateway subchart, which includes:
- Ingress gateway deployment
- Gateway service
- HorizontalPodAutoscaler

## Installation

```bash
helm install istio-gateway . --namespace istio-gateway --create-namespace
```

## Version

- Chart Version: 1.23.6
- Istio Version: 1.23.6


