#!/bin/bash
set -e

for CHART in $@; do
    CHARTPATH=$(dirname ${CHART})
    echo "gh-pages/${CHARTPATH}-$(awk -F: '/^version:/{gsub(/ /, "", $2);print $2}' ${CHART}).tgz"
done

