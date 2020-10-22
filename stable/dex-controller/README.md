*NOTE*: This chart will be hosted in [`dex-controller`](https://github.com/mesosphere/dex-controller) repo from v0.3.0.
The helm repo is: https://mesosphere.github.io/dex-controller/charts

# Dex controller helm chart

This is a `helm` chart that installs [`dex-controller`](https://github.com/mesosphere/dex-controller).

All the supported values and their defaults are listed below.

```yaml
controller:
  replicas: 1
  manager:
    image: mesosphere/dex-controller:v0.1.1
    imagePullPolicy: IfNotPresent
    resources:
      limits:
        cpu: 100m
        memory: 30Mi
      requests:
        cpu: 100m
        memory: 20Mi
  proxy:
    image: gcr.io/kubebuilder/kube-rbac-proxy:v0.4.0
    imagePullPolicy: IfNotPresent
    resources: {}
```
