#!/usr/bin/env bash

# This script upgrades the prometheus operator by copying all the latest upstream helm files.
#
# It then applies all the needed mesosphere changes from the /patch folder.
#
# To upgrade, simply run:
#   ./upgrade_operator.sh

set -xeuo pipefail
shopt -s dotglob

BASEDIR=$(dirname "$(realpath "$0")")
UPSTREAM_REPO=git@github.com:istio/istio.git
ISTIO_PATH=manifests/charts/istio-operator
ISTIO_DASHBOARDS_PATH=manifests/addons/dashboards
FORK_DASHBOARDS_PATH=charts/grafana/dashboards
ISTIO_TAG=1.22.3
TMPDIR=$(mktemp -d)
STARTING_REV=$(git rev-parse HEAD)
export STARTING_REV
trap 'rollback' ERR

rollback() {
    set +x
    echo "ERROR running upgrades. Rolling back."
    cd "${BASEDIR}"
    git reset --hard "${STARTING_REV}"
    exit 1
}

cd "${TMPDIR}" || exit

git init
git remote add origin -f ${UPSTREAM_REPO}
git config core.sparsecheckout true

echo ${ISTIO_PATH} > .git/info/sparse-checkout
echo ${ISTIO_DASHBOARDS_PATH} >> .git/info/sparse-checkout

git fetch origin ${ISTIO_TAG}
git checkout ${ISTIO_TAG}

cd ${ISTIO_PATH} || exit

for f in *; do
  rm -rf "${BASEDIR:?}"/"${f}"
  cp -R "$f" "${BASEDIR}"
done

cd "${BASEDIR}" || exit

git add .
git commit -am "chore: copy upstream chart ${ISTIO_TAG}"

cd "${TMPDIR}/${ISTIO_DASHBOARDS_PATH}" || exit

for f in *; do
  rm -rf "${BASEDIR:?}"/${FORK_DASHBOARDS_PATH}"/${f}"
  cp -R "$f" "${BASEDIR}/${FORK_DASHBOARDS_PATH}"
done

cd "${BASEDIR}" || exit

git add .
git diff-index --quiet HEAD || git commit -am "chore: copy upstream chart grafana dashboards ${ISTIO_TAG}"

BASEDIR=${BASEDIR} ISTIO_TAG=${ISTIO_TAG} ./patch/patch.sh

echo "Done upgrading istio!"
