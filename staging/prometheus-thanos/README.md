# prometheus-thanos

This is an umbrella chart which is a combination of [prometheus-operator](https://github.com/mesosphere/charts/tree/master/staging/prometheus-operator) and [Thanos](https://github.com/banzaicloud/banzai-charts/tree/master/thanos) charts. 

This chart is used to create/configure/manage Prometheus clusters atop Kubernetes with full power and functianlity of Thanos. 

For more documentation and configuration options please refer to the upstream charts documentation

- [mesosphere/charts/prometheus-operator](https://github.com/mesosphere/charts/tree/master/staging/prometheus-operator)
- [Thanos](https://github.com/banzaicloud/banzai-charts/tree/master/thanos)


## Configuration

The following tables list the configurable parameters of the prometheus-operator chart and their default values.

### General
| Parameter | Description | Default |
| ----- | ----------- | ------ |
| `prometheus-operator.enabled` | Specifies whether the [prometheus-operator](https://github.com/mesosphere/charts/tree/master/staging/prometheus-operator) subchart will be deployed. `true`/`false` | `true` |
| `prometheus-operator.VALUE` | Any of the configuration parameters of the [prometheus-operator](https://github.com/mesosphere/charts/tree/master/staging/prometheus-operator#general) subchart can be used in place of the `VALUE`| |
| `thanos.enabled` | Specifies whether the [Thanos](https://github.com/banzaicloud/banzai-charts/tree/master/thanos) subchart will be deployed. `true`/`false` | `true` |
| `thanos.query.enabled` | Specifies whether the [Query](https://github.com/thanos-io/thanos/blob/master/docs/components/query.md) component of Thanos will be deployed. `true`/`false` | `false` |
| `thanos.store.enabled` | Specifies whether the [Store](https://github.com/thanos-io/thanos/blob/master/docs/components/store.md) component of Thanos will be deployed. `true`/`false` | `false` |
| `thanos.compact.enabled` | Specifies whether the [Compact](https://github.com/thanos-io/thanos/blob/master/docs/components/compact.md) component of Thanos will be deployed. `true`/`false`| `false` |
| `thanos.bucket.enabled` | Specifies whether the [Bucket](https://github.com/thanos-io/thanos/blob/master/docs/components/bucket.md) component of Thanos will be deployed. `true`/`false` | `false` |
| `thanos.VALUE` | Any of the configuration parameters of the [Thanos]((https://github.com/banzaicloud/banzai-charts/tree/master/thanos)) subchart can be used in place of the `VALUE`| |

