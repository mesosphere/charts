#!/usr/bin/env bash

source $(dirname "$0")/helpers.sh

set -xeuo pipefail

patch -d "${BASEDIR}" -p3 --no-backup-if-mismatch < patch/mesosphere/patch/11_use_existing_storage_definitions.patch

git_add_and_commit "${BASEDIR}"/templates
