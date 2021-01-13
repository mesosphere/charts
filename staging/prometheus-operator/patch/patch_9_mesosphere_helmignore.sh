#!/usr/bin/env bash

# This patch adds mesosphere specific patterns to ignore into .helmignore

source $(dirname "$0")/helpers.sh

set -x

SRCFILE="${BASEDIR}"/.helmignore

sed -i '' -e '/# Mesosphere-specific files to ignore/,$d' ${SRCFILE}

cat << EOF >> ${SRCFILE}
# Mesosphere-specific files to ignore
patch/
EOF

git_add_and_commit "${BASEDIR}"/.helmignore
