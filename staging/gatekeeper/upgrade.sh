#!/usr/bin/env bash

# This script upgrades the gatekeeper by copying all the latest upstream helm files.
# 
# It then applies all the needed mesosphere changes from the /patch folder.
#
# To upgrade, simply run: 
#   ./upgrade_operator.sh

set -x

UPSTREAM_REPO=git@github.com:open-policy-agent/gatekeeper.git
GATEKEEPER_PATH=charts/gatekeeper
GATEKEEPER_TAG=v3.6.0
# if using osx download coreutils via brew and use greadlink instead
BASEDIR=$(dirname $(readlink -f "$0"))
TMPDIR=$(mktemp -d)

cd "${TMPDIR}" || exit

git init
git remote add origin -f ${UPSTREAM_REPO}
git config core.sparsecheckout true

echo ${GATEKEEPER_PATH} > .git/info/sparse-checkout

git pull origin master
git checkout ${GATEKEEPER_TAG}

cd ${GATEKEEPER_PATH} || exit

for f in $(ls -A); do
  rm -rf "${BASEDIR:?}"/"${f}"
  cp -R "$f" "${BASEDIR}"
done

cd "${BASEDIR}" || exit

NEW_VERSION=$(grep version Chart.yaml)

git add .
git commit -am "chore: copy upstream chart ${NEW_VERSION}"

BASEDIR=${BASEDIR} ./patch/patch.sh

echo "Done upgrading gatekeeper!"
