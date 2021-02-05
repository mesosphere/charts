#!/usr/bin/env bash
set -euo pipefail
cd $1
find * -prune -type d | while IFS= read -r d; do
  echo "attempting to bump $d"
  cd $d
  if [ -f requirements.yaml ]; then
    bump_requirements --user=mesosphere --project=charts --bump-option=sliced --dependencies=*;
  fi
  cd ..
done
