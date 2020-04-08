# Kubecost helm chart

This is a parent chart that deploys [Kubecost](https://kubecost.com/) along with some other supporting components.


```yaml
hooks:
  # This hook modifies the prometheus configmap to set the prometheus cluster_id
  # external label to the cluster's kube-system ns uid.
  clusterID:
    enabled: true
    kubectlImage: "bitnami/kubectl:1.16.2"

cost-analyzer:
  enabled: true

  global:
    prometheus:
      enabled: true # If false, Prometheus will not be installed -- only actively supported on paid Kubecost plans
      fqdn: http://cost-analyzer-prometheus-server.default.svc #example fqdn. Ignored if enabled: true

    thanos:
      enabled: false

    grafana:
      enabled: false # If false, Grafana will not be installed
      domainName: prometheus-kubeaddons-grafana.kubeaddons.svc # Ignored if enabled: true
      #scheme: "http" # http or https, for the domain name above.

  # Define persistence volume for cost-analyzer
  persistentVolume:
    size: 0.2Gi
    enabled: true # Note that setting this to false means configurations will be wiped out on pod restart.
    # storageClass: "-" #

  prometheus:
    nodeExporter:
      enabled: false
    serviceAccounts:
      nodeExporter:
        create: false
    extraScrapeConfigs: |
      - job_name: kubecost
        honor_labels: true
        scrape_interval: 1m
        scrape_timeout: 10s
        metrics_path: /metrics
        scheme: http
        dns_sd_configs:
        - names:
          - kubecost-kubeaddons-cost-analyzer
          type: 'A'
          port: 9003
      - job_name: kubecost-networking
        kubernetes_sd_configs:
          - role: pod
        relabel_configs:
        # Scrape only the the targets matching the following metadata
          - source_labels: [__meta_kubernetes_pod_label_app]
            action: keep
            regex: kubecost-kubeaddons-network-costs
    server:
      global:
        scrape_interval: 1m
        scrape_timeout: 10s
        evaluation_interval: 1m
        external_labels:
          cluster_id: $CLUSTER_ID
      persistentVolume:
        size: 32Gi
        enabled: true
      extraArgs:
        storage.tsdb.min-block-duration: 2h
        storage.tsdb.max-block-duration: 2h
        storage.tsdb.retention: 2w
      # extraVolumes: # TODO
      # - name: object-store-volume
      #   secret:
      #     # Ensure this secret name matches thanos.storeSecretName
      #     secretName: kubecost-thanos
      enableAdminApi: true
      service:
        gRPC:
          enabled: true
      sidecarContainers:
      - name: thanos-sidecar
        image: thanosio/thanos:v0.10.1
        args:
        - sidecar
        - --log.level=debug
        - --tsdb.path=/data/
        - --prometheus.url=http://127.0.0.1:9090
        # - --objstore.config-file=/etc/config/object-store.yaml # TODO
        # Start of time range limit to serve. Thanos sidecar will serve only metrics, which happened
        # later than this value. Option can be a constant time in RFC3339 format or time duration
        # relative to current time, such as -1d or 2h45m. Valid duration units are ms, s, m, h, d, w, y.
        - --min-time=-3h
        env:
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        ports:
        - name: sidecar-http
          containerPort: 10902
        - name: grpc
          containerPort: 10901
        - name: cluster
          containerPort: 10900
        volumeMounts:
        - name: config-volume
          mountPath: /etc/prometheus
        - name: storage-volume
          mountPath: /data
          subPath: ""
        # - name: object-store-volume # TODO
        #   mountPath: /etc/config
    alertmanager:
      enabled: false
    pushgateway:
      enabled: false

  thanos:
    store:
      enabled: false
    query:
      enabled: false
    sidecar:
      enabled: false
    bucket:
      enabled: false
    compact:
      enabled: false
    # This secret name should match the sidecar configured secret name volume
    # in the prometheus.server.extraVolumes entry
    # storeSecretName: kubecost-thanos # TODO
```
