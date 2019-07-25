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

| Parameter               | Description                                                                                    | Default        |
| ----------------------- | ---------------------------------------------------------------------------------------------- | -------------- |
| `global.serviceLabels`  | Additional labels for all service definitions in every Knative component, specified as a map.  | `{}`           |
| `serving.domain`        | Domain for the serving component.                                                              | `example.com`  |

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
