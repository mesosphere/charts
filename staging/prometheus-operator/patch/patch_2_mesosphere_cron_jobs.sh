#!/usr/bin/env bash

set -x

for c in $(ls ${BASEDIR}/patch/mesosphere/templates/grafana/cron*); do
  cp ${c} ${BASEDIR}/templates/grafana
done
