# Knative

[Knative](https://knative.dev/) is a Kubernetes-based platform to build, deploy, and manage modern
serverless workloads.

## Introduction

This chart bootstraps Knative's serving and eventing components with the GitHub eventing source in
the `knative-serving`, `knative-eventing` and `knative-sources` namespaces.

## Prerequisites

- Kubernetes 1.14+ with Beta APIs enabled

## A Quick Note on Versioning

The version references _only_ the revision of the chart itself. The `appVersion` field in
`Chart.yaml` conveys information regarding the revision of Knative that the chart provides.

## Installing the Chart

You must install Istio before installing the chart. Please follow the
[Installing Istio for Knative guide](https://knative.dev/docs/install/installing-istio/) to install
Istio on your Kubernetes cluster.

To install the chart with the release name `knative-release`:

```bash
$ helm install staging/knative --name knative-release
```

## Uninstalling the Chart

You must remove all Knative services and eventing sources before uninstalling the chart. Use the
commands below to uninstall the `knative-release` deployment and clean up all CRDs:

```bash
$ helm delete knative-release
$ kubectl get crds --output jsonpath='{.items..metadata.name}' \
  --selector knative.dev/crd-install=true | xargs kubectl delete crd
```

## Configuration

The following table lists the configurable parameters of the Knative chart and their default values.

| Parameter                                                 | Description                                                                                   | Default                       |
|-----------------------------------------------------------|-----------------------------------------------------------------------------------------------|-------------------------------|
| `global.serviceLabels`                                    | Additional labels for all service definitions in every Knative component, specified as a map. | `{}`                          |
| `serving.domain`                                          | Domain for the serving component.                                                             | `example.com`                 |
| `serving.autoscaler.containerConcurrencyTargetPercentage` | Specifies value in ConfigMap `config-autoscaler`, `container-concurrency-target-percentage`     | `70`                          |
| `serving.autoscaler.containerConcurrencyTargetDefault`    | Specifies value in ConfigMap `config-autoscaler`, `container-concurrency-target-default`        | `100`                         |
| `serving.autoscaler.requestsPerSecondTargetDefault`       | Specifies value in ConfigMap `config-autoscaler`, `requests-per-second-target-default`          | `200`                         |
| `serving.autoscaler.targetBurstCapacity`                  | Specifies value in ConfigMap `config-autoscaler`, `target-burst-capacity`                       | `200`                         |
| `serving.autoscaler.stableWindow`                         | Specifies value in ConfigMap `config-autoscaler`, `stable-window`                               | `60s`                         |
| `serving.autoscaler.panicWindowPercentage`                | Specifies value in ConfigMap `config-autoscaler`, `panic-window-percentage`                     | `10.0`                        |
| `serving.autoscaler.panicThresholdPercentage`             | Specifies value in ConfigMap `config-autoscaler`, `panic-threshold-percentage`                  | `200.0`                       |
| `serving.autoscaler.maxScaleUpRate`                       | Specifies value in ConfigMap `config-autoscaler`, `max-scale-up-rate`                           | `1000.0`                      |
| `serving.autoscaler.maxScaleDownRate`                     | Specifies value in ConfigMap `config-autoscaler`, `max-scale-down-rate`                         | `2.0`                         |
| `serving.autoscaler.enableScaleToZero`                    | Specifies value in ConfigMap `config-autoscaler`, `enable-scale-to-zero`                        | `true`                        |
| `serving.autoscaler.scaleToZeroGracePeriod`               | Specifies value in ConfigMap `config-autoscaler`, `scale-to-zero-grace-period`                  | `30s`                         |
| `serving.autoscaler.scaleToZeroPodRetentionPeriod`        | Specifies value in ConfigMap `config-autoscaler`, `scale-to-zero-pod-retention-period`          | `0s`                          |
| `serving.autoscaler.podAutoscalerClass`                   | Specifies value in ConfigMap `config-autoscaler`, `pod-autoscaler-class`                        | `kpa.autoscaling.knative.dev` |
| `serving.autoscaler.activatorCapacity`                    | Specifies value in ConfigMap `config-autoscaler`, `activator-capacity`                          | `100.0`                       |
| `serving.autoscaler.initialScale`                         | Specifies value in ConfigMap `config-autoscaler`, `initial-scale`                               | `1`                           |
| `serving.autoscaler.allowZeroInitialScale`                | Specifies value in ConfigMap `config-autoscaler`, `allow-zero-initial-scale`                    | `false`                       |
| `serving.autoscaler.maxScale`                             | Specifies value in ConfigMap `config-autoscaler`, `max-scale`                                   | `0`                           |

Specify each parameter using the `--set key=value[,key=value]` argument to `helm install`. For example:

```bash
$ helm install --name knative-release \
  --set serving.domain=1.2.3.4.nip.io staging/knative
```

The above command installs the serving component on the domain `1.2.3.4.nip.io`, so a Knative
application service `my-app` in the default namespace is accessible through
`my-app.default.1.2.3.4.nip.io`.

Alternatively, a YAML file that specifies the values for the parameters can be provided while
installing the chart. For example:

```bash
$ helm install --name knative-release --values values.yaml staging/knative
```
