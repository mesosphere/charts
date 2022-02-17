# Istio

[Istio](https://istio.io/) is an open platform for providing a uniform way to integrate microservices, manage traffic flow across microservices, enforce policies and aggregate telemetry data.

The documentation here is for developers only, please follow the installation instructions from [istio.io](https://istio.io/docs/setup/kubernetes/install/helm/) for all other uses.

## Introduction

This chart bootstraps all Istio [components](https://istio.io/docs/concepts/what-is-istio/) deployment on a [Kubernetes](http://kubernetes.io) cluster using the [Helm](https://helm.sh) package manager.

## Chart Details

This chart can install multiple Istio components as subcharts:
- grafana
- prometheus
- security

To enable or disable each component, change the corresponding `enabled` flag.

## Prerequisites

- Kubernetes 1.9 or newer cluster with RBAC (Role-Based Access Control) enabled is required
- Helm 2.7.2 or newer or alternately the ability to modify RBAC rules is also required
- If you want to enable automatic sidecar injection, Kubernetes 1.9+ with `admissionregistration` API is required, and `kube-apiserver` process must have the `admission-control` flag set with the `MutatingAdmissionWebhook` and `ValidatingAdmissionWebhook` admission controllers added and listed in the correct order.

## Resources Required

The chart deploys pods that consume minimum resources as specified in the resources configuration parameter.

## Installing the Chart

1. Set and create the namespace where Istio was installed:

    ```bash
    $ NAMESPACE=istio-system
    $ kubectl create ns $NAMESPACE
    ```

1. To install the chart with the release name `istio` in namespace $NAMESPACE you defined above:

    - With [automatic sidecar injection](https://istio.io/docs/setup/kubernetes/sidecar-injection/#automatic-sidecar-injection) (requires Kubernetes >=1.9.0):

        ```bash
        $ helm install istio --name istio --namespace $NAMESPACE
        ```

    - Without the sidecar injection webhook:

        ```bash
        $ helm install istio --name istio --namespace $NAMESPACE --set sidecarInjectorWebhook.enabled=false
        ```

## Configuration

The Helm chart ships with reasonable defaults.  There may be circumstances in which defaults require overrides.
To override Helm values, use `--set key=value` argument during the `helm install` command.  Multiple `--set` operations may be used in the same Helm operation.

Helm charts expose configuration options which are currently in alpha.  The currently exposed options can be found [here](https://istio.io/docs/reference/config/installation-options/).

## Uninstalling the Chart

To uninstall/delete the `istio` release but continue to track the release:

```bash
$ helm delete istio
```

To uninstall/delete the `istio` release completely and make its name free for later use:

```bash
$ helm delete --purge istio
```

## Steps to upgrade Istio chart

This chart wraps Istio Operator so the main component that needs to be updated is the Istio operator version. However, occasionally you might also have to update grafana dashboards and prometheus servicemonitor. Below is the step by step process to upgrade this istio chart:
- Download latest istio [release](https://github.com/istio/istio/releases/)
- Istio release is in the form of a tarball. Untar it. You will get istio-VERSION directory
- Compare and update *crds* and *templates* from istio-operator chart at 'istio-VERSION/manifests/charts/istio-operator'
- Compare and update *charts/grafana/dashboards* from 'istio-VERSION/samples/addons/grafana.yaml' \
  Useful commands:
  ```bash
  $ jq . pilot.yaml > istio-pilot-dashboard.json   -- where pilot.yaml is the pilot dashboard section of grafana.yaml
  ```
  ```bash
  $ yaml2json < service.yaml > service.json
  $ jq '.|fromjson' service.json > istio-service-dashboard.json
  ```
