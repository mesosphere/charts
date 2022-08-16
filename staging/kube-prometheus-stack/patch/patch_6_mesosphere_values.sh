#!/usr/bin/env bash

# This patch adds mesosphere specific chart values.
# These are the values we reference in our custom templates.

source $(dirname "$0")/helpers.sh

set -xeuo pipefail

SRCFILE="${BASEDIR}"/values.yaml

sed -i '.bak' '/# Create mesosphere specific resources/,$d' ${SRCFILE}

cat << EOF >> ${SRCFILE}
# Create mesosphere specific resources
mesosphereResources:
  create: false
  rules:
    elasticsearch: false
    velero: false
  hooks:
    kubectlImage: bitnami/kubectl:1.24.1
    prometheus:
      jobName: prom-get-cluster-id
      configmapName: cluster-info-configmap
  ingressRBAC:
    enabled: true
EOF

git_add_and_commit "${BASEDIR}"/values.yaml
