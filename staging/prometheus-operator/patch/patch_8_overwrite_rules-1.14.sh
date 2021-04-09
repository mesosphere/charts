#!/usr/bin/env bash

# This patch overwrites any rules within the rules-1.14/ dir.

source $(dirname "$0")/helpers.sh

set -xeuo pipefail

TEMPLATES_PATH="${BASEDIR}"/templates/prometheus/rules-1.14

cp ${BASEDIR}/patch/mesosphere/templates/rules/rules-1.14/* ${TEMPLATES_PATH}

if !git diff --exit-code; then
    git_add_and_commit "${TEMPLATES_PATH}"
fi
