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
    cronJob:
      enabled: false
  hooks:
    prometheus:
      jobName: prom-get-cluster-id
      kubectlImage: bitnami/kubectl:1.21.3
      configmapName: cluster-info-configmap
  ingressRBAC:
    enabled: true
EOF

git_add_and_commit "${BASEDIR}"/values.yaml
