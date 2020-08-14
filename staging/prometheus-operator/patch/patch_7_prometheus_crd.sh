#!/bin/bash

source $(dirname "$0")/helpers.sh

set -x

SRCFILE=crds/crd-prometheus.yaml
TMPFILE=crds/tmp-prom.yaml

docker run --rm -it \
  -v ${BASEDIR}:/basedir \
  -w /basedir \
  -e SRCFILE=${SRCFILE} \
  -e TMPFILE=${TMPFILE} \
  mikefarah/yq:3.3.2 \
  yq read -P "${SRCFILE}" > "${TMPFILE}" && mv "${TMPFILE}" "${SRCFILE}"

git_add_and_commit_with_msg ${SRCFILE} "reformat yaml with yq"

docker run --rm -it \
  -v ${BASEDIR}:/basedir \
  -w /basedir \
  -e SRCFILE=${SRCFILE} \
  -e TMPFILE=${TMPFILE} \
  mikefarah/yq:3.3.2 \
  yq write -i "${SRCFILE}" spec.validation.openAPIV3Schema.properties.spec.properties.storage.properties.volumeClaimTemplate.properties.metadata.properties.name.description "Name is the name used in the PVC claim" && \
  yq write -i "${SRCFILE}" spec.validation.openAPIV3Schema.properties.spec.properties.storage.properties.volumeClaimTemplate.properties.metadata.properties.name.type "string"

git_add_and_commit_with_msg ${SRCFILE} "update volumeClaimTemplate"

