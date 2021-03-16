#!/bin/bash

set -euo pipefail

patches=($(ls patch/patch_*.sh | sort -V))

for p in ${patches[*]}; do
    echo "Executing $p"
    BASEDIR=${BASEDIR} $p
done
