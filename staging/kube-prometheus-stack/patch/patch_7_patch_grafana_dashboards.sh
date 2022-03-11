#!/usr/bin/env bash

source $(dirname "$0")/helpers.sh

set -xeuo pipefail

patch -d "${BASEDIR}" -p3 --no-backup-if-mismatch < patch/mesosphere/patch/7_grafana_dashboards_use_default_datasource.patch

git_add_and_commit "${BASEDIR}"/templates
