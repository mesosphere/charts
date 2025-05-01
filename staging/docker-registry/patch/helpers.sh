#!/usr/bin/env bash

function git_add_and_commit {
  FILES_PATH=$1
  PATCH_FILE_NAME=$(basename "$2")
  git add "${FILES_PATH}"
  git commit -m "chore: apply ${PATCH_FILE_NAME}"
}

function git_add_and_commit_with_msg {
  FILES_PATH=$1
  MSG=$2
  git add "${FILES_PATH}"
  FILENAME=$(basename "$0")
  git commit -m "chore: apply ${FILENAME} - ${MSG}"
}
