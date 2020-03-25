# Kubecost helm chart

This chart deploys [Kubecost](https://kubecost.com/) configured for Kommander, along with supporting resources and addons.
This chart is intended to be used only as a subchart of the `kommander` chart.

All the supported values and their defaults are listed below:

```yaml
# Internal address for the cluster's Kubecost Thanos gRPC service.
# thanosAddress: "HOST:PORT"
thanosAddress: ""

federate:
  addons: true
  addonsInitializer:
    repository: "mesosphere/kubeaddons-addon-initializer"
    tag: "v0.1.1"
    pullPolicy: IfNotPresent
  addonNamespace:
    name: kubecost
  systemNamespace:
    name: kommander-system

portalRBAC:
  enabled: true
```
