#!/usr/bin/env bash

# This patch adds all of our ingress rbac rules

source $(dirname "$0")/helpers.sh

set -xeuo pipefail

TEMPLATES_PATH="${BASEDIR}"/templates/ingress-rbac

mkdir -p "${TEMPLATES_PATH}"

cp "${BASEDIR}"/patch/mesosphere/templates/ingress-rbac/* "${TEMPLATES_PATH}"

git_add_and_commit "${TEMPLATES_PATH}"
