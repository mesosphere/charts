#!/usr/bin/env bash

set -x

TEMPLATES_PATH=${BASEDIR}/templates/ingress-rbac

mkdir -p ${TEMPLATES_PATH}

cp ${BASEDIR}/patch/mesosphere/templates/ingress-rbac/* ${TEMPLATES_PATH}
