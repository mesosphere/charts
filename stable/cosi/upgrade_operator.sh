#!/usr/bin/env bash

# This script upgrades the cosi chart by copying all the latest upstream helm files.
#
# It then applies all the needed mesosphere changes from the /patch folder.
#
# To upgrade, simply run:
#   ./upgrade_operator.sh

set -xeuo pipefail
shopt -s dotglob

BASEDIR=$(dirname "$(realpath "$0")")
UPSTREAM_REPO=git@github.com:kubernetes-sigs/container-object-storage-interface.git
TAG=7ddc93baaa3f08c9c8990a17c7b958955d93c044 # Replace this with a real tag
KUSTOMIZATION_PATH=kustomization.yaml
CRDS_PATH=client/config/crd/
CONTROLLER_PATH=controller
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

echo ${KUSTOMIZATION_PATH} > .git/info/sparse-checkout
echo ${CRDS_PATH} >> .git/info/sparse-checkout
echo ${CONTROLLER_PATH} >> .git/info/sparse-checkout

git fetch origin ${TAG}
git checkout ${TAG}

mkdir chart
kustomize build --output chart .

# Let Helm create the namespace
rm chart/v1_namespace_container-object-storage-system.yaml # No need to create a namespace explicitly, helm will take care of it.
for f in chart/*; do
  rm -rf "${BASEDIR:?}"/templates/"${f}"
  sed -i 's/namespace: container-object-storage-system/namespace: {{ .Release.Namespace }}/g' "$f"
  cp -R "$f" "${BASEDIR}"/templates
done
sed -i '/^\s*namespace: default$/d' chart/rbac.authorization.k8s.io_v1_clusterrole_container-object-storage-controller-role.yaml

for f in chart/apiextensions.k8s.io_v1_customresourcedefinition*; do
  rm -rf "${BASEDIR:?}"/crds/"${f}"
  mv "$f" "${BASEDIR}"/crds
done
for f in chart/*; do
  rm -rf "${BASEDIR:?}"/templates/"${f}"
  cp -R "$f" "${BASEDIR}"/templates
done

cd "${BASEDIR}" || exit

# TODO(takirala): Add patching logic here (e.g. patch the priority class)

#git add .
#git commit -am "chore: copy upstream manifests @ ${TAG}"

echo "Done upgrading cosi!"
