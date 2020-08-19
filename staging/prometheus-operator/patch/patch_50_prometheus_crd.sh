#!/bin/bash

if [[ -z $(command -v yq) ]]; then
    echo "$0 requires the 'yq' command line tool which is not installed. Please install this and start again."
    exit 1
fi

SRCFILE="crds/crd-prometheus.yaml"
TMPFILE=$(mktemp)
yq -y '.spec.validation.openAPIV3Schema.properties.spec.properties.storage.properties.volumeClaimTemplate.properties.metadata.properties.name = {"description": "Name is the name used in the PVC claim", "type": "string"}' ${SRCFILE} >> ${TMPFILE}
mv ${TMPFILE} ${SRCFILE}

