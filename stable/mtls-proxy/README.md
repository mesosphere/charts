# mTLS Proxy Helm Chart

This chart deploys a [ghostunnel](https://github.com/square/ghostunnel) as a proxy that terminates mTLS connections for an insecure target service.
Support among ingress controllers for gRPC and mTLS isn't yet widespread or mature, so this chart is a simpler alternative to expose services using those protocols.

All the supported values and their defaults are listed below:

```yaml
replicaCount: 1

image:
  repository: squareup/ghostunnel
  tag: v1.5.1
  pullPolicy: IfNotPresent

imagePullSecrets: []
nameOverride: ""
fullnameOverride: ""

service:
  type: ClusterIP
  port: 443

ingress:
  enabled: false
  annotations: {}
  hosts: []

resources: {}

nodeSelector: {}

tolerations: []

affinity: {}

# TCP service to proxy.
# target: "HOST:PORT"
target: ""

# Secret containing server and CA certificates.
# Must contain tls.crt, tls.key, and ca.crt.
certSecretName: ""
```
