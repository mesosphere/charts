#!/usr/bin/env bash

# This patch adds new additional template manifests

source $(dirname "$0")/helpers.sh

set -xeuo pipefail

TEMPLATES_PATH="${BASEDIR}"/templates/

mkdir -p "${TEMPLATES_PATH}"

cp "${BASEDIR}"/patch/templates/* "${TEMPLATES_PATH}"

git_add_and_commit "${TEMPLATES_PATH}"
