#!/usr/bin/env bash

set -x

TEMPLATES_PATH=${BASEDIR}/templates/mesosphere-hooks

mkdir -p ${TEMPLATES_PATH}

cp ${BASEDIR}/patch/mesosphere/templates/hooks/* ${TEMPLATES_PATH}
