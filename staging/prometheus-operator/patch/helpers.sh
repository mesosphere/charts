#!/usr/bin/env bash

function git_add_and_commit {
  FILES_PATH=$1
  git add ${FILES_PATH}
  FILENAME=$(basename "$0")
  git commit -m "Apply ${FILENAME}"
}

