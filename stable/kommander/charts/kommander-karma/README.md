# Kommander Karma Helm chart

This chart deploys [Karma](https://github.com/prymitive/karma) configured for Kommander, along with supporting resources and addons.
This chart is intended to be used only as a subchart of the `kommander` chart.

All the supported values and their defaults are listed below:

```yaml
# Internal address for the cluster's alertmanager.
# alertmanagerAddress: "HOST:PORT"
alertmanagerAddress: ""
# Kommander service account used to delete the karma configmap
kommanderServiceAccount: kommander-kubeaddons
# Name of the karma configmap
kommanderKarmaConfigMap: kommander-kubeaddons-config

federate:
  addons: true
  systemNamespace:
    name: kommander-system

karma:
  service:
    labels:
      servicemonitor.kubeaddons.mesosphere.io/path: "kommander__monitoring__karma__metrics"

  ingress:
    enabled: true
    annotations:
      kubernetes.io/ingress.class: "traefik"
      traefik.ingress.kubernetes.io/auth-response-headers: "X-Forwarded-User"
      traefik.ingress.kubernetes.io/auth-type: "forward"
      traefik.ingress.kubernetes.io/auth-url: "http://traefik-forward-auth-kubeaddons.kubeaddons.svc.cluster.local:4181/"
      traefik.ingress.kubernetes.io/priority: "2"
    path: "/ops/portal/kommander/monitoring/karma"
    hosts:
      - ""

  livenessProbe:
    delay: 5
    period: 5
    path: /ops/portal/kommander/monitoring/karma/

  configMap:
    enabled: true
    rawConfig:
      alertmanager:
        interval: 30s
        servers:
          # Karma won't start without at least one configured alertmanager. We include a placeholder so that Karma will
          # successfully start. The placeholder URI's hostname should not resolve. This placeholder will be removed
          # once the corresponding controller discovers a managed cluster and updates this configuration with its
          # alertmanager.
          - name: placeholder
            uri: https://placeholder.invalid
      annotations:
        default:
          hidden: false
        hidden:
          - help
        visible: []
      filters:
        default: []
      labels:
        color:
          static:
            - job
          unique:
            - cluster
            - instance
            - "@receiver"
        keep: []
        strip: []
      listen:
        address: "0.0.0.0"
        port: 8080
        prefix: /ops/portal/kommander/monitoring/karma/
      log:
        config: true
        level: info

  certSecretNames:
    - kommander-karma-client-tls
```
