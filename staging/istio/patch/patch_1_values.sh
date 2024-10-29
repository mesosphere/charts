#!/usr/bin/env bash

source $(dirname "$0")/helpers.sh

set -xeuo pipefail

patch -d "${BASEDIR}" -p3 --no-backup-if-mismatch < patch/patches/1_values.patch

SRCFILE="${BASEDIR}"/values.yaml
gsed -i "s/ISTIO_VERSION_REPLACE/${ISTIO_TAG}/g" ${SRCFILE}

git_add_and_commit "${SRCFILE}"
