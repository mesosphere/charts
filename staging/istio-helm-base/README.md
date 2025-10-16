# istio-helm-base

Helm chart for deploying Istio base resources and CRDs.

## Overview

This chart contains only the Istio base subchart, which includes:
- Istio Custom Resource Definitions (CRDs)
- Base cluster resources

## Installation

```bash
helm install istio-base . --namespace istio-system --create-namespace
```

## Version

- Chart Version: 1.23.6
- Istio Version: 1.23.6

