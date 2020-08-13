#/usr/bin/env bash

source $(dirname "$0")/helpers.sh

set -x

cat << EOF >> ${BASEDIR}/values.yaml

# Create mesosphere specific resources
mesosphereResources:
  create: false
  rules:
    etcd: true
    velero: false
  dashboards:
    autoscaler: true
    calico: true
    elasticsearch: true
    fluentbit: true
    grafana: true
    opsportal: true
    kibana: true
    localvolumeprovisioner: true
    traefik: true
    velero: true
  homeDashboard:
    name: "Kubernetes / Compute Resources / Cluster"
    cronJob:
      name: set-grafana-home-dashboard
      image: dwdraju/alpine-curl-jq
  hooks:
    grafana:
      image: dwdraju/alpine-curl-jq
      secretKeyRef: ops-portal-credentials
      # serviceURL is deprecated, do not use
      serviceURL: http://prometheus-kubeaddons-grafana.kubeaddons:3000
    prometheus:
      jobName: prom-get-cluster-id
      kubectlImage: bitnami/kubectl:1.16.2
      configmapName: cluster-info-configmap
  ingressRBAC:
    enabled: true
EOF

git_add_and_commit ${BASEDIR}/values.yaml
