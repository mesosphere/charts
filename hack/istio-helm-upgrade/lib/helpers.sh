#!/usr/bin/env bash

# Shared helpers for the istio-helm upgrade flow.
#
# Expects REPO_ROOT to be exported by the caller and charts.sh to be sourced
# (for CHART_REGISTRY / upstream_chart_name).

# Pull an upstream chart at a tag and extract it into <destdir>/<name>,
# replacing anything already there. Normalizes the extracted directory to
# <name> even if the published chart name differs.
function pull_upstream_chart {
  local name="$1"
  local tag="$2"
  local destdir="$3"
  local uname
  uname=$(upstream_chart_name "${name}")
  rm -rf "${destdir:?}/${name}" "${destdir:?}/${uname}"
  helm pull "${CHART_REGISTRY}/${uname}" --version "${tag}" --untar --untardir "${destdir}"
  if [ "${uname}" != "${name}" ]; then
    mv "${destdir}/${uname}" "${destdir}/${name}"
  fi
}

# Replay our customizations onto a freshly pulled upstream tree.
#
# Our customizations are, by definition, the difference between the upstream we
# are currently on (base) and our live chart (live). We reproduce that same
# difference on top of the new upstream (result), file by file, using a 3-way
# merge so that upstream's own changes to a file are preserved and only genuine
# overlaps become conflicts.
#
#   live   = staging/istio-helm-<name>/charts/<name>   (source of truth)
#   base   = upstream chart at the CURRENT version
#   result = upstream chart at the NEW version (mutated in place)
#
# Prints the relative path of any file that could not be merged cleanly (one per
# line) to stdout; informational notes go to stderr.
function replay_customizations {
  local live="$1"
  local base="$2"
  local result="$3"
  local rel

  # Files we added or modified relative to the upstream we came from.
  while IFS= read -r rel; do
    if [ ! -e "${base}/${rel}" ]; then
      # A file we added -> carry it over verbatim.
      mkdir -p "${result}/$(dirname "${rel}")"
      cp "${live}/${rel}" "${result}/${rel}"
    elif ! cmp -s "${base}/${rel}" "${live}/${rel}"; then
      # A file we modified -> replay our change onto the new upstream copy.
      if [ ! -e "${result}/${rel}" ]; then
        mkdir -p "${result}/$(dirname "${rel}")"
        cp "${live}/${rel}" "${result}/${rel}"
        echo "  note: upstream removed ${rel}; kept our modified copy" >&2
      elif ! git merge-file --quiet "${result}/${rel}" "${base}/${rel}" "${live}/${rel}" 2>/dev/null; then
        echo "${rel}"
      fi
    fi
  done < <(cd "${live}" && find . -type f | sed 's|^\./||')

  # Files we deleted relative to the upstream we came from.
  while IFS= read -r rel; do
    if [ ! -e "${live}/${rel}" ] && [ -e "${result}/${rel}" ]; then
      rm -f "${result}/${rel}"
    fi
  done < <(cd "${base}" && find . -type f | sed 's|^\./||')
}

# Stage everything under the given path and commit, but only if there is
# something to commit.
function git_commit_if_changes {
  local path="$1"
  local msg="$2"
  git -C "${REPO_ROOT}" add -A "${path}"
  if git -C "${REPO_ROOT}" diff --cached --quiet -- "${path}"; then
    echo "No changes to commit for: ${msg}"
    return 0
  fi
  git -C "${REPO_ROOT}" commit -q -m "${msg}"
}

# Portable in-place sed (works with both GNU and BSD/macOS sed).
function sed_inplace {
  local expr="$1"
  local file="$2"
  local tmp
  tmp=$(mktemp)
  sed "${expr}" "${file}" > "${tmp}" && mv "${tmp}" "${file}"
}

# Replace the old Istio version string with the new one in a wrapper-level file
# (Chart.yaml / values.yaml). This only touches Istio version references: the
# mesosphere sub-chart versions (grafana/prometheus-operator/security) and the
# kubectl image tags never equal the Istio tag, so they are left untouched.
function bump_istio_version {
  local file="$1"
  local old="$2"
  local new="$3"
  [ -f "${file}" ] || return 0
  [ "${old}" = "${new}" ] && return 0
  sed_inplace "s/${old//./\\.}/${new}/g" "${file}"
}
