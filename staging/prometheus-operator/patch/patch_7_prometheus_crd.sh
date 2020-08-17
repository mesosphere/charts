#!/bin/bash

# This patch updates crd values needed to deploy properly in KBA.
#
# We use the yq docker image to manipulate the crd file. Due to the image's
# underlying go-yaml parser, updating a file automatically formats the yaml
# removing empty newlines and converting multiline strings into one line.
# See https://github.com/mikefarah/yq/issues/465#issuecomment-643863154

# This makes it hard to see the actual changes needed for the crd.
# Thus, we break the patches into smaller commits.
#
# - let yq format the file with no new added changes
# - update the volumeClaimTemplate.properties.metadata

source $(dirname "$0")/helpers.sh

set -x

SRCFILE=crds/crd-prometheus.yaml
TMPFILE=crds/tmp-prom.yaml

# let yq format the file
docker run --rm -it \
  -v ${BASEDIR}:/basedir \
  -w /basedir \
  -e SRCFILE=${SRCFILE} \
  -e TMPFILE=${TMPFILE} \
  mikefarah/yq:3.3.2 \
  yq read -P "${SRCFILE}" > "${TMPFILE}" && mv "${TMPFILE}" "${SRCFILE}"

git_add_and_commit_with_msg ${SRCFILE} "reformat yaml with yq (no new changes)"

# update volumeClaimTemplate.properties.metadata
docker run --rm -it \
  -v ${BASEDIR}:/basedir \
  -w /basedir \
  -e SRCFILE=${SRCFILE} \
  -e TMPFILE=${TMPFILE} \
  mikefarah/yq:3.3.2 \
  yq write -i "${SRCFILE}" spec.validation.openAPIV3Schema.properties.spec.properties.storage.properties.volumeClaimTemplate.properties.metadata.properties.name.description "Name is the name used in the PVC claim" && \
  yq write -i "${SRCFILE}" spec.validation.openAPIV3Schema.properties.spec.properties.storage.properties.volumeClaimTemplate.properties.metadata.properties.name.type "string"

git_add_and_commit_with_msg ${SRCFILE} "update volumeClaimTemplate"
