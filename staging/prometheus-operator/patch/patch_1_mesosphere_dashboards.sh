#!/usr/bin/env bash

set -x

TEMPLATES_PATH=${BASEDIR}/templates/grafana/dashboards/mesosphere-dashboards

mkdir -p ${TEMPLATES_PATH}

cp ${BASEDIR}/patch/mesosphere/templates/grafana/dashboards/* ${TEMPLATES_PATH}
