# istio-helm-gateway

Helm chart for deploying Istio ingress gateway.

## Overview

This chart contains only the Istio gateway subchart, which includes:
- Ingress gateway deployment
- Gateway service
- HorizontalPodAutoscaler

## Chart Structure

This is a wrapper chart that contains the upstream Istio gateway chart as a subchart located in `charts/gateway/`.


## Proxy Image Configuration

The gateway uses the Istio proxy (envoy) container. By default, the image is set to `auto`, which means Istio's mutating webhook will automatically inject the correct proxy image at runtime based on the installed Istio version.

To override the proxy image, you can set:
```yaml
gateway:
  #custom configuration for proxy image
  proxy:
    image: auto  # Default: auto-injected by Istio webhook
    # Or specify explicitly:
    # image: docker.io/istio/proxyv2:1.23.6
```

**Note:** Using `image: auto` is the recommended approach as it ensures the proxy version matches your Istio control plane version.

## Installation

```bash
helm install istio-helm-gateway . --namespace istio-gateway --create-namespace
```

## Version

- Chart Version: 1.23.6
- Istio Version: 1.23.6


