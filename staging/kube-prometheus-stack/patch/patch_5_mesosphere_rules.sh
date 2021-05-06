#!/usr/bin/env bash

# This patch adds alertmanager rules for certain addons

source $(dirname "$0")/helpers.sh

set -xeuo pipefail

TEMPLATES_PATH="${BASEDIR}"/templates/prometheus/rules/mesosphere-rules

mkdir -p "${TEMPLATES_PATH}"

cp "${BASEDIR}"/patch/mesosphere/templates/rules/mesosphere-rules/* "${TEMPLATES_PATH}"

git_add_and_commit "${TEMPLATES_PATH}"
