#!/usr/bin/env bash

source $(dirname "$0")/helpers.sh

set -x

TEMPLATES_PATH=${BASEDIR}/templates/grafana/dashboards/mesosphere-dashboards

mkdir -p ${TEMPLATES_PATH}

cp ${BASEDIR}/patch/mesosphere/templates/grafana/dashboards/* ${TEMPLATES_PATH}

git_add_and_commit ${TEMPLATES_PATH}
