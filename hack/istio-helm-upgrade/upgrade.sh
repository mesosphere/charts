#!/usr/bin/env bash

# Automated upgrade for the istio-helm-* fork charts.
#
# We pull the upstream Istio Helm charts (base, cni, gateway, istiod, ztunnel)
# under staging/istio-helm-<name>/charts/<name> and keep a small set of
# customizations directly in those charts.
#
# There is nothing to author or maintain besides the charts themselves: our
# customizations are simply however the live chart differs from the upstream it
# was pulled from. This script upgrades by:
#   1. pulling the upstream we are currently on (the "base"),
#   2. pulling the target upstream,
#   3. replaying our diff (base -> live) onto the target via a 3-way merge,
#   4. bumping the wrapper-level version references.
#
# Files upstream also changed merge automatically; a genuine overlap stops the
# run and leaves conflict markers for you to resolve. On any other error the
# working tree is rolled back.
#
# Usage:
#   ./upgrade.sh 1.30.0          # upgrade to a specific tag

# -E (errtrace) is required so the ERR/rollback trap also fires for failures
# inside helper functions (e.g. helm pull), not just top-level commands.
set -Eeuo pipefail
shopt -s dotglob

# Pinned default. Bump this (or pass a tag) when upgrading.
DEFAULT_ISTIO_TAG=1.29.0
ISTIO_TAG="${1:-${ISTIO_TAG:-${DEFAULT_ISTIO_TAG}}}"

BASEDIR=$(dirname "$(realpath "$0")")
REPO_ROOT=$(git -C "${BASEDIR}" rev-parse --show-toplevel)
STARTING_REV=$(git -C "${REPO_ROOT}" rev-parse HEAD)
export BASEDIR REPO_ROOT ISTIO_TAG

source "${BASEDIR}/lib/charts.sh"
source "${BASEDIR}/lib/helpers.sh"

# The Istio version we are upgrading *from*, read from a wrapper Chart.yaml.
OLD_ISTIO_TAG=$(sed -n 's/^appVersion:[[:space:]]*//p' "${REPO_ROOT}/staging/istio-helm-base/Chart.yaml" | head -1)

rollback() {
    set +x
    echo "ERROR running upgrade. Rolling back to ${STARTING_REV}." >&2
    git -C "${REPO_ROOT}" reset --hard "${STARTING_REV}"
    exit 1
}
trap 'rollback' ERR

TMPDIR=$(mktemp -d)
trap 'rm -rf "${TMPDIR}"' EXIT

echo "Upgrading istio-helm charts ${OLD_ISTIO_TAG} -> ${ISTIO_TAG}"

CONFLICTS=""

for name in "${CHARTS[@]}"; do
    wrapper="${REPO_ROOT}/staging/istio-helm-${name}"
    live="${wrapper}/charts/${name}"
    [ -d "${live}" ] || continue

    echo "==> ${name}"
    pull_upstream_chart "${name}" "${OLD_ISTIO_TAG}" "${TMPDIR}/base"
    pull_upstream_chart "${name}" "${ISTIO_TAG}" "${TMPDIR}/new"

    # Replay our customizations (base -> live) onto the new upstream tree.
    chart_conflicts=$(replay_customizations "${live}" "${TMPDIR}/base/${name}" "${TMPDIR}/new/${name}")
    if [ -n "${chart_conflicts}" ]; then
        CONFLICTS+="  ${name}:"$'\n'
        CONFLICTS+=$(echo "${chart_conflicts}" | sed 's|^|    charts/'"${name}"'/|')$'\n'
    fi

    # Swap the merged result in for the vendored sub-chart.
    rm -rf "${live}"
    mkdir -p "${live}"
    cp -R "${TMPDIR}/new/${name}"/* "${live}/"

    # Bump the wrapper-level Istio version references (appVersion + sub-chart
    # dependency version in Chart.yaml, and pinned image tag in values.yaml).
    bump_istio_version "${wrapper}/Chart.yaml" "${OLD_ISTIO_TAG}" "${ISTIO_TAG}"
    bump_istio_version "${wrapper}/values.yaml" "${OLD_ISTIO_TAG}" "${ISTIO_TAG}"
done

if [ -n "${CONFLICTS}" ]; then
    # Conflicts are expected human decisions, not script failures: keep the
    # merged tree (with markers) so they can be resolved, and do not roll back.
    trap - ERR
    echo
    echo "Upgrade merged, but these files need manual conflict resolution" >&2
    echo "(edit the <<<<<<< / ======= / >>>>>>> markers, then commit):" >&2
    echo "${CONFLICTS}" >&2
    exit 1
fi

# Clean merge: commit one change per chart.
for name in "${CHARTS[@]}"; do
    wrapper="${REPO_ROOT}/staging/istio-helm-${name}"
    [ -d "${wrapper}/charts/${name}" ] || continue
    git_commit_if_changes "${wrapper}" "chore(${name}): upgrade istio to ${ISTIO_TAG}"
done

echo "Done upgrading istio-helm to ${ISTIO_TAG}!"
echo
echo "NOTE: bump each wrapper Chart.yaml 'version:' (chart packaging version) per"
echo "the release convention."
