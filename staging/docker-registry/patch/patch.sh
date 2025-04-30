#!/bin/bash

source $(dirname "$0")/helpers.sh

set -euo pipefail

declare -a patches
while IFS= read -r line; do
  patches+=("$line")
done < <(find patch/nutanix/*.patch | sort -V)

for p in ${patches[*]}; do
    echo "Executing $p"
    patch -d "${BASEDIR}" -p3 --no-backup-if-mismatch < $p
    git_add_and_commit "${BASEDIR}" $p
done
