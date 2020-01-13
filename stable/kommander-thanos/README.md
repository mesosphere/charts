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
    name: kommander-system

thanos:
  store:
    enabled: false
  compact:
    enabled: false
  bucket:
    enabled: false
  sidecar:
    enabled: false

  query:
    # Name of HTTP request header used for dynamic prefixing of UI links and redirects.
    webPrefixHeader: "X-Forwarded-Prefix"
    # Enable DNS discovery for stores
    storeDNSDiscovery: false
    # Enable DNS discovery for sidecars (this is for the chart built-in sidecar service)
    sidecarDNSDiscovery: false
    # Addresses of statically configured store API servers (repeatable).
    stores: []
    # Names of configmaps that contain addresses of store API servers, used for file service discovery.
    serviceDiscoveryFileConfigMaps:
    - kommander-thanos-query-stores
    # Refresh interval to re-read file SD files. It is used as a resync fallback.
    serviceDiscoveryInterval: 5m
    # Add extra arguments to the compact service
    extraArgs:
    - "--grpc-client-tls-secure"
    - "--grpc-client-tls-cert=/etc/certs/tls.crt"
    - "--grpc-client-tls-key=/etc/certs/tls.key"
    - "--grpc-client-tls-ca=/etc/certs/ca.crt"
    - "--grpc-client-server-name=server.thanos.localhost.localdomain"
    certSecretName: kommander-thanos-client-tls
    http:
      ingress:
        enabled: true
        annotations:
          kubernetes.io/ingress.class: "traefik"
          traefik.frontend.rule.type: "PathPrefixStrip"
          traefik.ingress.kubernetes.io/auth-response-headers: "X-Forwarded-User"
          traefik.ingress.kubernetes.io/auth-type: "forward"
          traefik.ingress.kubernetes.io/auth-url: "http://traefik-forward-auth-kubeaddons.kubeaddons.svc.cluster.local:4181/"
          traefik.ingress.kubernetes.io/priority: "2"
        path: "ops/portal/kommander/monitoring/query"
        hosts:
          - ""
        tls: []
```
