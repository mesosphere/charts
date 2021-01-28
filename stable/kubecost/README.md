# Kubecost helm chart

This is a parent chart that deploys [Kubecost](https://kubecost.com/) along with some other supporting components.


```yaml
hooks:
  # Modifies the prometheus configmap to set the prometheus cluster_id
  # external label to the cluster's kube-system ns uid.
  # Creates configmap to pass kube-system ns uid as envvar to kubecost.
  clusterID:
    enabled: true
    kubectlImage: "bitnami/kubectl:1.19.2"

cost-analyzer:
  enabled: true

  global:
    prometheus:
      # If false, Prometheus will not be installed -- only actively supported on paid Kubecost plans
      enabled: true

    thanos:
      enabled: false

    grafana:
      # If false, Grafana will not be installed
      enabled: true

  # Enable kubecost ingress with below annotations to use Konvoy traefik auth
  # ingress:
  #   enabled: true
  #   annotations:
  #     kubernetes.io/ingress.class: traefik
  #     ingress.kubernetes.io/auth-response-headers: X-Forwarded-User
  #     traefik.frontend.rule.type: PathPrefixStrip
  #     traefik.ingress.kubernetes.io/auth-response-headers: X-Forwarded-User,Authorization,Impersonate-User,Impersonate-Group
  #     traefik.ingress.kubernetes.io/auth-type: forward
  #     # traefik rules need to be overridden to use kommander auth if federated from kommander
  #     traefik.ingress.kubernetes.io/auth-url: http://traefik-forward-auth-kubeaddons.kubeaddons.svc.cluster.local:4181/
  #     traefik.ingress.kubernetes.io/priority: "2"
  #   paths:
  #     - "/ops/portal/kubecost"
  #   hosts:
  #     - ""
  #   tls: []

  # Define persistence volume for cost-analyzer
  persistentVolume:
    size: 0.2Gi
    # Note that setting this to false means configurations will be wiped out on pod restart.
    enabled: true
    # storageClass: "-"

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
          - {{ .Release.Name }}-cost-analyzer
          type: 'A'
          port: 9003
      - job_name: kubecost-networking
        kubernetes_sd_configs:
          - role: pod
        relabel_configs:
        # Scrape only the the targets matching the following metadata
          - source_labels: [__meta_kubernetes_pod_label_app]
            action: keep
            regex: {{ .Release.Name }}-network-costs
    server:
      global:
        scrape_interval: 1m
        scrape_timeout: 10s
        evaluation_interval: 1m
        external_labels:
          cluster_id: $CLUSTER_ID
          configmap_key_ref: kubecost-cluster-info-configmap
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
        - --reloader.config-file=/etc/config/prometheus.yml
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
          mountPath: /etc/config
        - name: storage-volume
          mountPath: /data
          subPath: ""
        # - name: object-store-volume # TODO
        #   mountPath: /etc/config
    alertmanager:
      enabled: false
    pushgateway:
      enabled: false
      persistentVolume:
        enabled: false

  grafana:
    sidecar:
      dashboards:
        enabled: true
        label: kubecost_grafana_dashboard
      datasources:
        enabled: true
        defaultDatasourceEnabled: true
        label: kubecost_grafana_datasource
    # Enable grafana ingress with below annotations to use Konvoy traefik auth
    # ingress:
    #   enabled: true
    #   annotations:
    #     kubernetes.io/ingress.class: traefik
    #     ingress.kubernetes.io/auth-response-headers: X-Forwarded-User
    #     traefik.frontend.rule.type: PathPrefixStrip
    #     traefik.ingress.kubernetes.io/auth-response-headers: X-Forwarded-User,Authorization,Impersonate-User,Impersonate-Group
    #     traefik.ingress.kubernetes.io/auth-type: forward
    #     # traefik rules need to be overridden to use kommander auth if federated from kommander
    #     traefik.ingress.kubernetes.io/auth-url: http://traefik-forward-auth-kubeaddons.kubeaddons.svc.cluster.local:4181/
    #     traefik.ingress.kubernetes.io/priority: "2"
    #   hosts: [""]
    #   path: /ops/portal/kubecost/grafana
    grafana.ini:
      server:
        protocol: http
        enable_gzip: true
        root_url: "%(protocol)s://%(domain)s:%(http_port)s/ops/portal/kubecost/grafana"
      auth.proxy:
        enabled: true
        header_name: X-Forwarded-User
        auto-sign-up: true
      auth.basic:
        enabled: false
      users:
        auto_assign_org_role: Admin

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
