#!/usr/bin/env bash

# This patch adds all crds that may be required, for now it adds
# the mutations crd, which we hope will be part of gatekeeper releases soon


source $(dirname "$0")/helpers.sh

set -x

CRDS_PATH=${BASEDIR}/crds

mkdir -p "${CRDS_PATH}"

cp "${BASEDIR}"/patch/crds/* "${CRDS_PATH}"

git_add_and_commit "${CRDS_PATH}"
