#!/usr/bin/env bash

# This patch adds back the check for `monitoring.coreos.com/v1` that was removed from upstream.

source $(dirname "$0")/helpers.sh

set -x

TEMPLATES_PATH=${BASEDIR}/templates/prometheus-operator/crds.yaml

rm -rf ${BASEDIR}/templates/prometheus-operator/crds.yaml
cp ${BASEDIR}/patch/mesosphere/templates/prometheus-operator/crds.yaml ${TEMPLATES_PATH}

git_add_and_commit ${TEMPLATES_PATH}
