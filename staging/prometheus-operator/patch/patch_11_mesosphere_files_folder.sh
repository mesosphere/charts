#!/usr/bin/env bash

# This patch adds mesosphere files to the files directory

source $(dirname "$0")/helpers.sh

set -x

FILES_PATH="${BASEDIR}"/files

mkdir -p "${FILES_PATH}"

cp "${BASEDIR}"/patch/mesosphere/files* "${FILES_PATH}"

git_add_and_commit "${FILES_PATH}"
