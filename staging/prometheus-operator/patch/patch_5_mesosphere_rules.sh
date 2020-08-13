#!/usr/bin/env bash

set -x

TEMPLATES_PATH=${BASEDIR}/templates/prometheus/rules/mesosphere-rules

mkdir -p ${TEMPLATES_PATH}

cp ${BASEDIR}/patch/mesosphere/templates/rules/* ${TEMPLATES_PATH}
