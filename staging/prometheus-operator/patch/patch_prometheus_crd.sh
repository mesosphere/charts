#!/bin/bash

SRCFILE="crds/crd-prometheus.yaml"
TMPFILE=$(mktemp)
yq -y '.spec.validation.openAPIV3Schema.properties.spec.properties.storage.properties.volumeClaimTemplate.properties.metadata.properties.name = {"description": "Name is the name used in the PVC claim", "type": "string"}' ${SRCFILE} >> ${TMPFILE}
mv ${TMPFILE} ${SRCFILE}

