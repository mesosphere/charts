#!/usr/bin/env bash

source $(dirname "$0")/helpers.sh

set -xeuo pipefail

patch -d "${BASEDIR}" -p3 --no-backup-if-mismatch < patch/patches/3_chartyaml.patch

# Replace hardcoded 1.0.0 chart version with istio tag
SRCFILE="${BASEDIR}"/Chart.yaml
gsed -i "s/1.0.0/${ISTIO_TAG}/g" ${SRCFILE}

git_add_and_commit "${SRCFILE}"
