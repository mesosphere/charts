#!/usr/bin/env bash

# This patch adds mesosphere specific patterns to ignore into .helmignore

source $(dirname "$0")/helpers.sh

set -xeuo pipefail

SRCFILE="${BASEDIR}"/.helmignore

sed -i '/# Mesosphere-specific files to ignore/,$d' ${SRCFILE}

cat << EOF >> ${SRCFILE}
# Mesosphere-specific files to ignore
upgrade_operator.sh
kube-prometheus-stack-*.tgz
patch/
EOF

git_add_and_commit "${BASEDIR}"/.helmignore
