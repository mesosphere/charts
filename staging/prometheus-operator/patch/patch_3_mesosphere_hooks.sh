#!/usr/bin/env bash

# This patch adds all of our custom hooks

source $(dirname "$0")/helpers.sh

set -xeuo pipefail

TEMPLATES_PATH="${BASEDIR}"/templates/mesosphere-hooks

mkdir -p "${TEMPLATES_PATH}"

cp "${BASEDIR}"/patch/mesosphere/templates/hooks/* "${TEMPLATES_PATH}"

git_add_and_commit "${TEMPLATES_PATH}"
