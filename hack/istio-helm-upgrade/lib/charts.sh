#!/usr/bin/env bash

# Single source of truth for the Istio wrapper charts this tooling manages.
#
# To manage a new wrapper chart, add its name here (and create the matching
# staging/istio-helm-<name> directory). upgrade.sh is driven off this list, so
# there is nothing else to wire up.
#
# Each entry <name> maps to:
#   - wrapper chart:        staging/istio-helm-<name>
#   - vendored sub-chart:   staging/istio-helm-<name>/charts/<name>
#   - upstream published:   ${CHART_REGISTRY}/$(upstream_chart_name <name>)

# Allow the caller to override the list (e.g. to run for a single chart).
if [ -z "${CHARTS:-}" ]; then
  CHARTS=(base cni gateway istiod ztunnel)
fi

# OCI registry that publishes the upstream Istio Helm charts.
CHART_REGISTRY="${CHART_REGISTRY:-oci://gcr.io/istio-release/charts}"

# The published upstream chart name for a given wrapper chart. Today every
# wrapper name matches its upstream chart name; add a case here if that ever
# stops being true (kept as a function so we stay compatible with bash 3.2,
# which has no associative arrays).
upstream_chart_name() {
  case "$1" in
    *) echo "$1" ;;
  esac
}
