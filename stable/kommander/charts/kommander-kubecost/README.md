# Kommander Thanos helm chart

This chart deploys [Thanos](https://github.com/thanos-io/thanos) configured for Kommander, along with supporting resources and addons.
This chart is intended to be used only as a subchart of the `kommander` chart.

All the supported values and their defaults are listed below:

```yaml
# Internal address for the cluster's Thanos gRPC service.
# thanosAddress: "HOST:PORT"
thanosAddress: ""
# Kommander service account used to delete Thanos store configmaps
kommanderServiceAccount: kommander-kubeaddons

federate:
  systemNamespace:
    name: kubecost
```
