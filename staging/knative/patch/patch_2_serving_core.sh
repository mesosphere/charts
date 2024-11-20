#!/usr/bin/env bash

source $(dirname "$0")/helpers.sh

set -xeuo pipefail

patch -d "${BASEDIR}" -p3 --no-backup-if-mismatch < patch/patches/01-serving-core-config-map-config-autoscaler.patch

SRCFILE="${BASEDIR}"/charts/serving/templates/serving-core.yaml

git_add_and_commit "${SRCFILE}"
