#!/bin/bash

set -euo pipefail

declare -a patches
while IFS= read -r line; do
  patches+=("$line")
done < <(find patch/patch_*.sh | sort -V)

for p in ${patches[*]}; do
    echo "Executing $p"
    BASEDIR=${BASEDIR} $p
done
