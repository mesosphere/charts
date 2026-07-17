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
# Requires: git, helm (>= 3.8, for OCI) and standard POSIX tools (bash, sed,
# find, cmp, mktemp) on PATH. Run on a CLEAN working tree / dedicated branch:
# on error the script hard-resets and discards uncommitted changes.
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

# Resolve the script's own directory without relying on realpath, which is not
# available on stock macOS. cd + pwd is portable across macOS and Linux.
BASEDIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(git -C "${BASEDIR}" rev-parse --show-toplevel)
STARTING_REV=$(git -C "${REPO_ROOT}" rev-parse HEAD)
export BASEDIR REPO_ROOT ISTIO_TAG

source "${BASEDIR}/lib/charts.sh"
source "${BASEDIR}/lib/helpers.sh"

# The Istio version we are upgrading *from* (the merge "base"), read from the
# istio-helm-base wrapper's appVersion. All wrapper charts are kept in lockstep
# on the same Istio appVersion, so base is representative. This value must match
# the upstream the charts were actually vendored from - if appVersion is edited
# out of sync, the 3-way merge base is wrong and the replay can misfire.
OLD_ISTIO_TAG=$(sed -n 's/^appVersion:[[:space:]]*//p' "${REPO_ROOT}/staging/istio-helm-base/Chart.yaml" | head -1)

# Set when we intentionally stop for manual conflict resolution. rollback()
# reads it to decide whether an exit is an expected conflict stop (keep the
# merged tree) or a genuine failure (hard-reset). See the conflict block below.
STOP_FOR_CONFLICTS=0

rollback() {
    set +x
    # A conflict stop is an expected outcome, not a failure: keep the merged
    # tree (with markers) so it can be resolved. Any *other* error hard-resets
    # to STARTING_REV and discards ALL uncommitted changes, including unrelated
    # ones - which is why the script must run on a clean working tree / branch.
    # This flag (not the ordering of a `trap - ERR`) decides the behaviour, so
    # the rollback path is not fragile to how/where we exit.
    if [ "${STOP_FOR_CONFLICTS:-0}" = "1" ]; then
        exit 1
    fi
    echo "ERROR running upgrade. Rolling back to ${STARTING_REV}." >&2
    git -C "${REPO_ROOT}" reset --hard "${STARTING_REV}"
    exit 1
}
trap 'rollback' ERR

TMPDIR=$(mktemp -d)
trap 'rm -rf "${TMPDIR}"' EXIT

echo "Upgrading istio-helm charts ${OLD_ISTIO_TAG} -> ${ISTIO_TAG}"

CONFLICTS=()

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
        while IFS= read -r cf; do
            [ -n "${cf}" ] && CONFLICTS+=("charts/${name}/${cf}")
        done <<< "${chart_conflicts}"
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

if [ "${#CONFLICTS[@]}" -gt 0 ]; then
    # Conflicts are expected human decisions, not script failures. Mark the run
    # so rollback() keeps the merged tree (with markers) instead of resetting,
    # then report and exit non-zero.
    STOP_FOR_CONFLICTS=1
    echo
    echo "Upgrade merged, but these files need manual conflict resolution" >&2
    echo "(edit the <<<<<<< / ======= / >>>>>>> markers, then commit):" >&2
    for cf in "${CONFLICTS[@]}"; do
        echo "  ${cf}" >&2
    done
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
