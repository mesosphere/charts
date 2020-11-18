#!/bin/bash
# NOTE: used by teamcity and dispatch

UNAME=$(uname | tr '[:upper:]' '[:lower:]')
KONVOY_VERSION="${KONVOY_VERSION:-v1.5.0}"
if ! [ -z $1 ]
then
    KONVOY_VERSION=$1
fi

set -euo pipefail

curl --silent https://downloads.mesosphere.io/konvoy/konvoy_${KONVOY_VERSION}_${UNAME}.tar.bz2 | tar xjv --strip=1 konvoy_${KONVOY_VERSION}/konvoy
