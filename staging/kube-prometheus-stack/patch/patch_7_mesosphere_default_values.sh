#!/bin/bash

# This patch updates default values needed to deploy properly in KBA.

source $(dirname "$0")/helpers.sh

set -xeuo pipefail

SRCFILE=values.yaml
TMPFILE=crds/values.yaml

# let yq format the file
docker run --rm -it \
  -v "${BASEDIR}":/basedir \
  -w /basedir \
  -e SRCFILE=${SRCFILE} \
  -e TMPFILE=${TMPFILE} \
  mikefarah/yq:3.3.2 \
  yq read -P "${SRCFILE}" > "${TMPFILE}" && mv "${TMPFILE}" "${SRCFILE}"

git_add_and_commit_with_msg ${SRCFILE} "reformat yaml with yq (no new changes)"

# 1. For this version we set probeSelectorNilUsesHelmValues value to false to allow updates of crds from version 9 to 11
# we should probably set to true for the next version bump


docker run --rm -it \
  -v "${BASEDIR}":/basedir \
  -w /basedir \
  -e SRCFILE=${SRCFILE} \
  -e TMPFILE=${TMPFILE} \
  mikefarah/yq:3.3.2 \
  yq write -i "${SRCFILE}" prometheus.prometheusSpec.probeSelectorNilUsesHelmValues false

git_add_and_commit_with_msg ${SRCFILE} "update values files"
