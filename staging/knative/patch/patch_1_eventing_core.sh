#!/usr/bin/env bash

source $(dirname "$0")/helpers.sh

set -xeuo pipefail

patch -d "${BASEDIR}" -p3 --no-backup-if-mismatch < patch/patches/00-eventing-core-config-map-config-features.patch

SRCFILE="${BASEDIR}"/charts/eventing/templates/eventing-core.yaml

git_add_and_commit "${SRCFILE}"
