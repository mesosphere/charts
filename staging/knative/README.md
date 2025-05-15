# Knative

[Knative](https://knative.dev/) is a Kubernetes-based platform to build, deploy, and manage modern
serverless workloads.

## Introduction

This chart bootstraps Knative's Serving and Eventing components using the Knative Operator. The operator manages the lifecycle of Knative components, simplifying deployment and upgrades.

## Prerequisites

- Kubernetes 1.24+ with Beta APIs enabled
- Istio installed on the cluster ([Installing Istio for Knative guide](https://knative.dev/docs/install/installing-istio/))

## Installing the Chart

To install the chart with the release name `knative-release`:

```bash
$ helm install knative-release staging/knative
```

This will deploy the Knative Operator along with the Serving and Eventing components.

## Uninstalling the Chart

To uninstall the `knative-release` deployment and clean up all CRDs:

```bash
$ helm delete knative-release
$ kubectl get crds --output jsonpath='{.items..metadata.name}' \
--selector knative.dev/crd-install=true | xargs kubectl delete crd
```

## Configuration

The following table lists the configurable parameters of the Knative chart and their default values.

| Parameter                  | Description                                                                 | Default       |
|----------------------------|-----------------------------------------------------------------------------|---------------|
| `knativeOperator.enabled`  | Enable or disable the Knative Operator                                      | `true`        |
| `serving.enabled`          | Enable or disable Knative Serving                                           | `true`        |
| `serving.manifest`         | Configuration for the Knative Serving manifest                             | See `values.yaml` |
| `eventing.enabled`         | Enable or disable Knative Eventing                                          | `true`        |
| `eventing.manifest`        | Configuration for the Knative Eventing manifest                            | See `values.yaml` |

Specify each parameter using the `--set key=value[,key=value]` argument to `helm install`. For example:

```bash
$ helm install knative-release \
--set serving.domain=1.2.3.4.nip.io staging/knative
```

Alternatively, a YAML file that specifies the values for the parameters can be provided while installing the chart. For example:

```bash
$ helm install knative-release --values values.yaml staging/knative
```

## Upgrading

The Knative Operator manages upgrades for Serving and Eventing components. To upgrade the chart, update the `Chart.yaml` dependencies and run:

```bash
$ helm dependency update staging/knative
$ helm upgrade knative-release staging/knative
```

Ensure that the `values.yaml` file reflects the desired configuration for the new version.
