#!/usr/bin/env bash

# This patch adds mesosphere custom template files

source $(dirname "$0")/helpers.sh

set -x

TEMPLATES_PATH=${BASEDIR}/templates/

# remove validation webhook to replace
rm "${TEMPLATES_PATH}/gatekeeper-validating-webhook-configuration-validatingwebhookconfiguration.yaml"

cp "${BASEDIR}"/patch/templates/* "${TEMPLATES_PATH}"

git_add_and_commit "${TEMPLATES_PATH}"
