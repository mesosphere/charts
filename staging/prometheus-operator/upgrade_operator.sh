#!/usr/bin/env bash

# This script upgrades the prometheus operator by copying all the latest upstream helm files.
# 
# It then applies all the needed mesosphere changes from the /patch folder.
#
# To upgrade, simply run: 
#   ./upgrade_operator.sh

set -xeuo pipefail
shopt -s dotglob

BASEDIR=$(dirname "$(readlink -f "$0")")
UPSTREAM_REPO=git@github.com:prometheus-community/helm-charts.git
PROMETHEUS_PATH=charts/kube-prometheus-stack
PROMETHEUS_TAG=kube-prometheus-stack-12.11.3
# if using osx download coreutils via brew and use greadlink instead
TMPDIR=$(mktemp -d)
STARTING_REV=$(git rev-parse HEAD)
export STARTING_REV
trap 'rollback' ERR

rollback() {
    cd "${BASEDIR}"
    git reset --hard "${STARTING_REV}"
}



cd "${TMPDIR}" || exit

git init
git remote add origin -f ${UPSTREAM_REPO}
git config core.sparsecheckout true

echo ${PROMETHEUS_PATH} > .git/info/sparse-checkout

git fetch origin ${PROMETHEUS_TAG}
git checkout ${PROMETHEUS_TAG}

cd ${PROMETHEUS_PATH} || exit

for f in *; do
  rm -rf "${BASEDIR:?}"/"${f}"
  cp -R "$f" "${BASEDIR}"
done

cd "${BASEDIR}" || exit

NEW_VERSION=$(grep version Chart.yaml)

git add .
git commit -am "chore: copy upstream chart ${NEW_VERSION}"

BASEDIR=${BASEDIR} ./patch/patch.sh

echo "Done upgrading prometheus-operator!"
