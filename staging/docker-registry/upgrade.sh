#!/usr/bin/env bash

# This script upgrades the docker-registry by copying all the latest upstream helm files.
# 
# It then applies all the needed mesosphere changes from the /patch folder.
#
# To upgrade, simply run: 
#   ./upgrade_operator.sh

set -xeuo pipefail
shopt -s dotglob

BASEDIR=$(dirname "$(realpath "$0")")
UPSTREAM_REPO=git@github.com:twuni/docker-registry.helm.git
REF=main
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

echo README.md > .git/info/sparse-checkout
echo LICENSE >> .git/info/sparse-checkout
echo Chart.yaml >> .git/info/sparse-checkout
echo templates/ >> .git/info/sparse-checkout
echo values.yaml >> .git/info/sparse-checkout

git fetch origin ${REF}
git checkout ${REF}

for f in *; do
  if [[ "$f" == ".git" ]]; then
    continue
  fi
  rm -rf "${BASEDIR:?}"/"${f}"
  cp -R "$f" "${BASEDIR}"
done

cd "${BASEDIR}" || exit

NEW_VERSION=$(grep -E '^version:' Chart.yaml)

git add .
git diff-index --quiet HEAD || git commit -am "chore: copy upstream chart ${NEW_VERSION}"

BASEDIR=${BASEDIR} ./patch/patch.sh

echo "Done upgrading docker-registry!"
