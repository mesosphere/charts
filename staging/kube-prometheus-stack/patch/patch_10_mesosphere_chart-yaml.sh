#!/usr/bin/env bash

# This patch replaces the kube-prometheus-stack name in favor of prometheus-operator

source $(dirname "$0")/helpers.sh

set -xeuo pipefail

SRCFILE="${BASEDIR}"/Chart.yaml

sed -i 's/kube-prometheus-stack/prometheus-operator/g' ${SRCFILE}


git_add_and_commit "${BASEDIR}"/Chart.yaml
