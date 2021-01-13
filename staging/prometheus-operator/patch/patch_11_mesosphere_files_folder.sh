#!/usr/bin/env bash

# This patch adds mesosphere specific patterns to ignore into .helmignore

source $(dirname "$0")/helpers.sh

set -x

SRCFILE="${BASEDIR}"/Chart.yaml

sed -i 's/kube-prometheus-stack/prometheus-operator/g' ${SRCFILE}


git_add_and_commit "${BASEDIR}"/Chart.yaml
