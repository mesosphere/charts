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

1. If a service account has not already been installed for Tiller, install one:

    ```bash
    $ kubectl apply -f install/kubernetes/helm/helm-service-account.yaml
    ```

1. Install Tiller on your cluster with the service account:

    ```bash
    $ helm init --service-account tiller
    ```

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
