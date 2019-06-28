#!/bin/bash
set -e

for CHART in $@; do
    CHARTPATH=$(dirname ${CHART})
    echo "docs/${CHARTPATH}-$(awk -F: '/^version:/{gsub(/ /, "", $2);print $2}' ${CHART}).tgz"
done

