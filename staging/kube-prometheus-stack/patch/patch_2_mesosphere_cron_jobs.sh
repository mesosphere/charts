#!/usr/bin/env bash

# This patch adds all our custom cronjobs

source $(dirname "$0")/helpers.sh

set -xeuo pipefail

GRAFANA_PATH=${BASEDIR}/templates/grafana

for c in "${BASEDIR}"/patch/mesosphere/templates/grafana/cron*; do
  [[ -e ${c} ]] || break # handle case when no files exist
  cp "${c}" "${GRAFANA_PATH}"
done

git_add_and_commit "${GRAFANA_PATH}"
