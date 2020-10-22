# konvoyconfig

This chart creates a ConfigMap in the kubeaddons namespace for the purpose of providing
shared configuration options to addons. Presently, this chart is only being used to supply
the `clusterHostname` variable to traefik, dex, dex-k8s-authenticator, and kube-oidc-proxy. 

In the event there is need for additional configurations, the configurations should added to
this chart.
