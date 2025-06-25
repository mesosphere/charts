# Registry Syncer Helm Chart

This directory contains the Helm chart for the Registry Syncer,
which is used to synchronize OCI artifacts between different registries.

It uses https://regclient.org/usage/regsync/.

The chart will deploy both a Job and a Deployment, allowing you to run the syncer initially as a one-time job 
and then continue to run it periodically as a deployment.

## Installing the Chart

First, add the repo:

```console
helm repo add mesosphere-staging https://mesosphere.github.io/charts/staging
```

To install the chart, use the following:

```console
helm install registry-syncer mesosphere-staging/registry-syncer
```

### Example Values

```yaml
deployment:
  config:
    creds:
      - registry: docker-registry.registry-system.svc.cluster.local:443
        tls: insecure
        reqPerSec: 1
    sync:
      - source: docker-registry.registry-system.svc.cluster.local:443
        target: another-registry.registry-system.svc.cluster.local:443
        type: registry
        interval: 1m
```