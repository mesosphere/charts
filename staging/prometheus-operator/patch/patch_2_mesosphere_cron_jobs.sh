#!/usr/bin/env bash

source $(dirname "$0")/helpers.sh

set -x

GRAFANA_PATH=${BASEDIR}/templates/grafana

for c in $(ls ${BASEDIR}/patch/mesosphere/templates/grafana/cron*); do
  cp ${c} ${GRAFANA_PATH}
done

git_add_and_commit ${GRAFANA_PATH}
