#!/usr/bin/env bash

# This patch adds mesosphere specific chart values.
# These are the values we reference in our custom templates.

source $(dirname "$0")/helpers.sh

set -xeuo pipefail

SRCFILE="${BASEDIR}"/values.yaml

sed -i '/# Create mesosphere specific resources/,$d' ${SRCFILE}

cat << EOF >> ${SRCFILE}
# Create mesosphere specific resources
mesosphereResources:
  create: false
  rules:
    elasticsearch: false
    velero: false
  homeDashboard:
    name: "Kubernetes / Compute Resources / Cluster"
    serviceNameOverride: ""
    cronJob:
      enabled: true
      name: set-grafana-home-dashboard
      image: apteno/alpine-jq:2021-01-19
  hooks:
    grafana:
      image: apteno/alpine-jq:2021-01-19
      secretKeyRef: dkp-credentials
    prometheus:
      jobName: prom-get-cluster-id
      kubectlImage: bitnami/kubectl:1.19.7
      configmapName: cluster-info-configmap
  ingressRBAC:
    enabled: true
EOF

git_add_and_commit "${BASEDIR}"/values.yaml
