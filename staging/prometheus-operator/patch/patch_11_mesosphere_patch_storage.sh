#!/usr/bin/env bash

source $(dirname "$0")/helpers.sh

set -x

patch -d "${BASEDIR}" -p3 < patch/mesosphere/patch/11_use_existing_storage_definitions.patch

git_add_and_commit "${BASEDIR}"/templates
