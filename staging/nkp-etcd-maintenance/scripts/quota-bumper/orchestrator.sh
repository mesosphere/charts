#!/usr/bin/env bash
# =============================================================================
# nkp-etcd-maintenance — etcd quota-bumper orchestrator
#
# Drives a zero-downtime, one-node-at-a-time roll-out of
# `--quota-backend-bytes` across all control-plane nodes of a kubeadm-managed
# Kubernetes cluster.
#
# This script is part of the nkp-etcd-maintenance Helm chart, but it is a
# WORKSTATION-side tool: Helm cannot template per-node, single-shot,
# throw-away Jobs cleanly, so this script renders the per-node Job template
# (../../files/quota-bumper/job-template.yaml) and applies one Job at a time.
#
# Prerequisites (installed by the chart when quotaBumper.enabled=true):
#   * ConfigMap        kube-system/etcd-quota-bumper-scripts
#   * ServiceAccount   kube-system/etcd-quota-bumper-sa
#   * ClusterRole      etcd-quota-bumper-role
#   * ClusterRoleBinding etcd-quota-bumper-rolebinding
#
# If the chart has NOT been told to install them, this script aborts in
# Phase 1 with the exact `helm upgrade` invocation to run first.
#
# Topology-agnostic: works on 1, 3, 5, or 7 control-plane nodes by
# discovering them from the API at run time.
#
# Phases:
#   1. Pre-flight     — verify chart prerequisites are installed; discover
#                       topology; assert quorum-safe size; assert cluster
#                       health; refuse to shrink quota; demand operator
#                       confirmation (unless --yes).
#   2. Rolling patch  — sequentially spawn one per-node Job at a time. Each
#                       Job backs up the host's etcd static-pod manifest,
#                       patches it, and waits for the kubelet to cycle the
#                       etcd container AND quorum to reform. ABORTS on the
#                       first per-node failure.
#   3. Post-flight    — `etcdctl endpoint status --cluster -w table` and a
#                       per-pod assertion that the running spec carries the
#                       target quota.
#
# Exit codes
#   0  success
#   1  pre-flight failure (chart not enabled / cluster unhealthy /
#      topology unsupported / shrink refused)
#   2  rolling-patch failure on at least one node (rollout aborted)
#   3  cluster-wide health check failed between two nodes
#   4  post-flight assertion failed (running spec lacks target quota)
# =============================================================================

# bash strict mode:
#   -E  ERR trap inherited by funcs/subshells
#   -e  exit on first error
#   -u  unset var = error (catches typos)
#   -o pipefail  pipeline fails if any stage fails (not just the last)
set -Eeuo pipefail

# -------------------- defaults (override via env or flags) -------------------
# Bash parameter expansion `${X:-default}` = use X if set & non-empty,
# else `default`. Lets each knob be overridden either by env or by CLI flag.
#
# Variables used throughout the orchestrator:
#   QUOTA_BYTES          — the target --quota-backend-bytes value, in bytes.
#                          8 GiB = 8 * 1024^3 = 8589934592.
#   NAMESPACE            — kube-system; not overridden in practice.
#   JOB_TIMEOUT_SECONDS  — wall-clock budget per per-node Job. Must be
#                          >= verify-restart.sh's VERIFY_TIMEOUT_SECONDS
#                          (360) plus pull + scheduling overhead.
#   KUBECTL_IMAGE        — image used by record-id + verify containers;
#                          must carry kubectl + /bin/sh.
#   DRY_RUN              — "1" = print rendered Jobs, don't apply.
#   AUTO_APPROVE         — "1" = skip the operator confirmation prompt.
QUOTA_BYTES="${QUOTA_BYTES:-8589934592}"           # 8 GiB
NAMESPACE="${NAMESPACE:-kube-system}"
JOB_TIMEOUT_SECONDS="${JOB_TIMEOUT_SECONDS:-600}"   # 10 min per node
KUBECTL_IMAGE="${KUBECTL_IMAGE:-docker.io/mesosphere/kubectl:v1.35.2-alpine}"
DRY_RUN="${DRY_RUN:-0}"
AUTO_APPROVE="${AUTO_APPROVE:-0}"

# `BASH_SOURCE[0]` = path to *this* script (even when sourced).
# `cd … && pwd` canonicalises the path (resolves "..", symlinks-ish).
# JOB_TEMPLATE = absolute path to the per-node Job YAML template
#                we'll render once per node.
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CHART_ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd)
JOB_TEMPLATE="${CHART_ROOT}/files/quota-bumper/job-template.yaml"

# -------------------- usage --------------------------------------------------
usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --quota-bytes N        Target value for --quota-backend-bytes.
                         Default: ${QUOTA_BYTES} (= 8 GiB).
  --job-timeout SEC      Per-node Job wait timeout in seconds.
                         Default: ${JOB_TIMEOUT_SECONDS}.
  --kubectl-image IMG    Image used for record-id + verify containers.
                         Default: ${KUBECTL_IMAGE}.
  --dry-run              Show what would happen; do not apply anything.
  --yes / -y             Skip the interactive confirmation prompt.
  -h / --help            This help.

Environment overrides:
  QUOTA_BYTES, JOB_TIMEOUT_SECONDS, KUBECTL_IMAGE, DRY_RUN=1, AUTO_APPROVE=1

Prerequisite — install the chart resources first:
  helm upgrade --install nkp-etcd-maintenance ${CHART_ROOT} \\
    --namespace nkp-etcd-maintenance --create-namespace \\
    --reuse-values --set quotaBumper.enabled=true
EOF
}

# -------------------- argparse ----------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --quota-bytes)     QUOTA_BYTES="$2";          shift 2 ;;
    --job-timeout)     JOB_TIMEOUT_SECONDS="$2";  shift 2 ;;
    --kubectl-image)   KUBECTL_IMAGE="$2";        shift 2 ;;
    --dry-run)         DRY_RUN=1;                 shift   ;;
    --yes|-y)          AUTO_APPROVE=1;            shift   ;;
    -h|--help)         usage; exit 0 ;;
    *)                 echo "Unknown arg: $1" >&2; usage >&2; exit 1 ;;
  esac
done

# -------------------- logging helpers ---------------------------------------
ts()  { date -u +%H:%M:%SZ; }
log() { printf '\033[1;36m[%s] %s\033[0m\n' "$(ts)" "$*"; }
ok()  { printf '\033[1;32m[%s] ✓ %s\033[0m\n' "$(ts)" "$*"; }
warn(){ printf '\033[1;33m[%s] ! %s\033[0m\n' "$(ts)" "$*"; }
err() { printf '\033[1;31m[%s] ✗ %s\033[0m\n' "$(ts)" "$*" >&2; }

run() {
  if [ "${DRY_RUN}" = "1" ]; then
    printf '\033[1;35m[dry-run] $ %s\033[0m\n' "$*"
  else
    "$@"
  fi
}

trap 'err "orchestrator died at line ${LINENO}"; exit 99' ERR

# Run etcdctl inside an existing etcd pod (no etcdctl needed on workstation).
etcdctl_exec() {
  local pod="$1"; shift
  kubectl -n "${NAMESPACE}" exec "${pod}" -- etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    --command-timeout=10s \
    "$@"
}

# Wait for a Job to reach a terminal condition (Complete or Failed).
# `kubectl wait --for=condition=Complete` blocks until Complete or the
# timeout — it does NOT return early on Failed, which is exactly what we
# need to avoid here.
#
# We disable the inherited ERR trap inside this function for two reasons:
#   1. On bash 3.2 (macOS default), `set -E` + `set +e` interact such that
#      ERR traps can still fire on a non-zero command inside a function,
#      even when the caller has disabled errexit around the call site.
#   2. We INTENTIONALLY use `[ ... ] && return N` which returns non-zero
#      when the condition is false — that's a feature, not an error.
wait_for_job() {
  trap - ERR
  local job="$1" deadline=$(( $(date +%s) + JOB_TIMEOUT_SECONDS ))
  while [ "$(date +%s)" -lt "${deadline}" ]; do
    local complete failed
    complete=$(kubectl -n "${NAMESPACE}" get job "${job}" \
      -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || true)
    failed=$(kubectl   -n "${NAMESPACE}" get job "${job}" \
      -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null || true)
    if [ "${complete}" = "True" ]; then
      trap 'err "orchestrator died at line ${LINENO}"; exit 99' ERR
      return 0
    fi
    if [ "${failed}" = "True" ]; then
      trap 'err "orchestrator died at line ${LINENO}"; exit 99' ERR
      return 1
    fi
    sleep 4
  done
  trap 'err "orchestrator died at line ${LINENO}"; exit 99' ERR
  return 2   # timeout
}

# ============================================================================
# Phase 1 — Pre-flight
# ============================================================================
log "==================== Phase 1 — Pre-flight ===================="

# --- Verify chart prerequisites are installed -------------------------------
# We deliberately do NOT `kubectl apply` the ConfigMap/RBAC here — those are
# Helm-managed (templates/quota-bumper/*.yaml gated on .Values.quotaBumper
# .enabled). If they're missing, fail loudly with the exact `helm upgrade`
# command rather than installing them out-of-band and confusing Helm state.
log "Checking for chart-managed prerequisites ..."
MISSING=0
for kind_name in \
    configmap/etcd-quota-bumper-scripts \
    serviceaccount/etcd-quota-bumper-sa \
    clusterrole/etcd-quota-bumper-role \
    clusterrolebinding/etcd-quota-bumper-rolebinding; do
  if ! kubectl -n "${NAMESPACE}" get "${kind_name}" >/dev/null 2>&1 \
     && ! kubectl get "${kind_name}" >/dev/null 2>&1; then
    err "missing: ${kind_name}"
    MISSING=1
  fi
done

if [ "${MISSING}" -eq 1 ]; then
  err "One or more chart-managed resources are not installed."
  err "Run:"
  err "  helm upgrade --install nkp-etcd-maintenance ${CHART_ROOT} \\"
  err "    --namespace nkp-etcd-maintenance --create-namespace \\"
  err "    --reuse-values --set quotaBumper.enabled=true"
  exit 1
fi
ok "All chart-managed prerequisites are present."

# --- Sanity-check the Job template exists on disk ---------------------------
if [ ! -f "${JOB_TEMPLATE}" ]; then
  err "Job template not found at ${JOB_TEMPLATE}"
  err "Are you running this from a valid checkout of the chart?"
  exit 1
fi

# --- Discover control-plane nodes via the modern label ----------------------
# Note: we use a `while read` loop (not `mapfile -t`) so this script runs on
# bash 3.2 (the default on macOS workstations). `mapfile` is a bash 4+
# builtin; depending on it would silently break operators who haven't
# `brew install bash`'d.
CP_NODES=()
while IFS= read -r line; do
  [ -n "${line}" ] && CP_NODES+=("${line}")
done < <(
  kubectl get nodes \
    -l node-role.kubernetes.io/control-plane \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
  | sort
)

if [ "${#CP_NODES[@]}" -eq 0 ]; then
  err "no control-plane nodes found via label node-role.kubernetes.io/control-plane"
  exit 1
fi

log "Discovered ${#CP_NODES[@]} control-plane node(s):"
for n in "${CP_NODES[@]}"; do echo "    - ${n}"; done

case "${#CP_NODES[@]}" in
  1) warn "single-node CP — there is NO quorum to lose, but there IS a downtime window per node (~30 s)." ;;
  3|5|7) : ;;
  *) err "${#CP_NODES[@]} control-plane nodes is not an odd-quorum size (1/3/5/7)."
     err "Refusing to proceed — a non-standard topology requires manual review."
     exit 1 ;;
esac

# --- Discover etcd static pods (kubeadm names them `etcd-<node>`) -----------
# Same bash-3.2-friendly `while read` pattern as above.
ETCD_PODS=()
while IFS= read -r line; do
  [ -n "${line}" ] && ETCD_PODS+=("${line}")
done < <(
  kubectl -n "${NAMESPACE}" get pods \
    -l component=etcd \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
  | sort
)

if [ "${#ETCD_PODS[@]}" -ne "${#CP_NODES[@]}" ]; then
  err "Found ${#ETCD_PODS[@]} etcd pod(s) but ${#CP_NODES[@]} CP node(s) — mismatch; aborting."
  err "Expected one etcd-<node> pod per control-plane node (kubeadm convention)."
  exit 1
fi
ok "etcd pod count matches CP node count: ${#ETCD_PODS[@]}"

# --- Initial cluster health -------------------------------------------------
# Refuse to start a roll-out on a degraded cluster.
log "Checking initial cluster health (etcdctl endpoint health --cluster) ..."
if ! etcdctl_exec "${ETCD_PODS[0]}" endpoint health --cluster -w table; then
  err "Cluster is NOT healthy — aborting. A degraded cluster cannot tolerate a rolling restart."
  exit 1
fi
ok "Cluster is healthy"

# --- Current quota per node (informational) ---------------------------------
log "Current --quota-backend-bytes per node:"
for n in "${CP_NODES[@]}"; do
  cur=$(kubectl -n "${NAMESPACE}" get pod "etcd-${n}" \
    -o jsonpath='{range .spec.containers[?(@.name=="etcd")].command[*]}{@}{"\n"}{end}' \
    | grep '^--quota-backend-bytes=' || echo "(unset → etcd default 2147483648)")
  echo "    ${n}: ${cur}"
done
log "Target: --quota-backend-bytes=${QUOTA_BYTES}"

# --- Refuse to shrink -------------------------------------------------------
# Refuse to set a value smaller than the current value anywhere (shrinking
# the quota on a >= current-usage etcd → NOSPACE).
for n in "${CP_NODES[@]}"; do
  cur=$(kubectl -n "${NAMESPACE}" get pod "etcd-${n}" \
    -o jsonpath='{range .spec.containers[?(@.name=="etcd")].command[*]}{@}{"\n"}{end}' \
    | grep '^--quota-backend-bytes=' | sed 's/^--quota-backend-bytes=//' || echo "2147483648")
  if [ "${cur}" -gt "${QUOTA_BYTES}" ]; then
    err "${n} currently has quota ${cur} bytes which is GREATER than the target ${QUOTA_BYTES}."
    err "Shrinking quota below current db size will trigger NOSPACE — refusing."
    err "If you really want to shrink, run defrag first and pass --quota-bytes >= dbSize."
    exit 1
  fi
done
ok "Target quota is not a shrink on any node."

# --- Operator confirmation --------------------------------------------------
if [ "${AUTO_APPROVE}" != "1" ] && [ "${DRY_RUN}" != "1" ]; then
  printf '\033[1;33m[%s] Proceed with rolling update on %d node(s)? [y/N] \033[0m' "$(ts)" "${#CP_NODES[@]}"
  read -r reply
  case "${reply}" in
    y|Y|yes|YES) : ;;
    *) log "aborted by user."; exit 0 ;;
  esac
fi

# ============================================================================
# Phase 2 — Rolling patch
# ============================================================================
log "==================== Phase 2 — Rolling patch ===================="

SKIPPED_OK=0
PATCHED_OK=0
for i in "${!CP_NODES[@]}"; do
  NODE="${CP_NODES[$i]}"

  # ---- node-level idempotency skip -----------------------------------------
  # Read CURRENT quota fresh for this node (state may have changed since the
  # pre-flight check, e.g. a prior Job in this same loop just succeeded).
  # If the node is already at the target value, skip it.
  #
  # Rationale: patch-manifest.sh is byte-idempotent at the YAML level, but
  # writing an identical manifest does NOT trigger kubelet to restart the
  # static pod (kubelet hashes parsed content). Skipping here is therefore
  # the ONLY safe option — proceeding would write a no-change manifest and
  # then deadlock verify-restart.sh step 1 (poll for containerID change)
  # until the per-node timeout fires.
  cur=$(kubectl -n "${NAMESPACE}" get pod "etcd-${NODE}" \
    -o jsonpath='{range .spec.containers[?(@.name=="etcd")].command[*]}{@}{"\n"}{end}' \
    | grep '^--quota-backend-bytes=' | sed 's/^--quota-backend-bytes=//' || echo "")
  if [ "${cur}" = "${QUOTA_BYTES}" ]; then
    ok "[node $((i+1))/${#CP_NODES[@]}] ${NODE}: already at --quota-backend-bytes=${QUOTA_BYTES}; skipping."
    SKIPPED_OK=$((SKIPPED_OK + 1))
    continue
  fi

  # Job name: include node, run-timestamp, and a short prefix for label-search.
  JOB_NAME="etcd-quota-bumper-$(echo "${NODE}" | tr '.' '-' | tr '[:upper:]' '[:lower:]' | cut -c1-35)-$(date +%s)"

  log "[node $((i+1))/${#CP_NODES[@]}] target=${NODE}  job=${JOB_NAME}"

  # Render the Job template.
  RENDERED=$(sed \
    -e "s|__JOB_NAME__|${JOB_NAME}|g" \
    -e "s|__NODE_NAME__|${NODE}|g" \
    -e "s|__QUOTA_BYTES__|${QUOTA_BYTES}|g" \
    -e "s|__KUBECTL_IMAGE__|${KUBECTL_IMAGE}|g" \
    "${JOB_TEMPLATE}")

  if [ "${DRY_RUN}" = "1" ]; then
    echo "----- dry-run: rendered Job for ${NODE} -----"
    echo "${RENDERED}"
    echo "----- end dry-run -----"
    continue
  fi

  echo "${RENDERED}" | kubectl apply -f -

  log "Waiting for Job ${JOB_NAME} to complete (timeout=${JOB_TIMEOUT_SECONDS}s) ..."
  set +e
  wait_for_job "${JOB_NAME}"
  rc=$?
  set -e

  case "${rc}" in
    0) ok "Job ${JOB_NAME} completed" ;;
    1)
      err "Job ${JOB_NAME} FAILED. Inspect with:"
      err "  kubectl describe job ${JOB_NAME} -n ${NAMESPACE}"
      err "  kubectl logs job/${JOB_NAME} -n ${NAMESPACE} --all-containers --prefix"
      echo
      kubectl logs "job/${JOB_NAME}" -n "${NAMESPACE}" --all-containers --prefix --tail=50 || true
      echo
      err "Rollout aborted. Remaining nodes NOT touched."
      err "Recovery: the host etcd.yaml on ${NODE} has a backup at"
      err "  /etc/kubernetes/manifests/etcd.yaml.bak.<timestamp>"
      err "If etcd is stuck on ${NODE}, restore that backup over etcd.yaml."
      exit 2
      ;;
    2)
      err "Job ${JOB_NAME} did not terminate within ${JOB_TIMEOUT_SECONDS}s."
      err "  kubectl describe job ${JOB_NAME} -n ${NAMESPACE}"
      err "  kubectl logs   job/${JOB_NAME} -n ${NAMESPACE} --all-containers --prefix"
      exit 2
      ;;
  esac

  # Echo the Job's log into the orchestrator output so the operator has a
  # single timeline of what happened across all nodes.
  kubectl logs "job/${JOB_NAME}" -n "${NAMESPACE}" --all-containers --prefix --tail=25

  # Extra defence: an independent cluster-health check from outside the
  # per-node Job. The Job already gated on `endpoint health --cluster`,
  # but a defence-in-depth check catches "Job thinks it's healthy but
  # the connection dropped between then and now" edge cases.
  log "Independent cluster-health check before next node ..."
  if ! etcdctl_exec "${ETCD_PODS[0]}" endpoint health --cluster; then
    err "Cluster health degraded between Job-complete and orchestrator check."
    err "Refusing to touch the next node."
    exit 3
  fi
  PATCHED_OK=$((PATCHED_OK + 1))
  ok "Cluster healthy — proceeding to next node"
  echo
done

log "Phase 2 summary: patched=${PATCHED_OK} skipped(already-ok)=${SKIPPED_OK} total=${#CP_NODES[@]}"

if [ "${DRY_RUN}" = "1" ]; then
  log "dry-run complete; no changes were applied."
  exit 0
fi

# ============================================================================
# Phase 3 — Post-flight validation
# ============================================================================
log "==================== Phase 3 — Post-flight ===================="

log "etcdctl endpoint status --cluster -w table:"
etcdctl_exec "${ETCD_PODS[0]}" endpoint status --cluster -w table

log "Per-node command-line audit (proves the flag is in the running pod spec on every node):"
ALL_OK=1
for n in "${CP_NODES[@]}"; do
  applied=$(kubectl -n "${NAMESPACE}" get pod "etcd-${n}" \
    -o jsonpath='{range .spec.containers[?(@.name=="etcd")].command[*]}{@}{"\n"}{end}' \
    | grep '^--quota-backend-bytes=' || echo "MISSING")
  if [ "${applied}" = "--quota-backend-bytes=${QUOTA_BYTES}" ]; then
    ok "${n}: ${applied}"
  else
    err "${n}: got '${applied}', expected '--quota-backend-bytes=${QUOTA_BYTES}'"
    ALL_OK=0
  fi
done

if [ "${ALL_OK}" -ne 1 ]; then
  err "POST-FLIGHT FAILED: not every node has the target quota."
  exit 4
fi

log "Optional — verify etcd's RUNTIME quota via its /metrics endpoint:"
for n in "${CP_NODES[@]}"; do
  metric=$(kubectl -n "${NAMESPACE}" exec "etcd-${n}" -- \
    sh -c 'wget -q -O- http://127.0.0.1:2381/metrics 2>/dev/null \
            | grep "^etcd_server_quota_backend_bytes " || echo "(metric not readable)"' \
    2>/dev/null || echo "(metric not readable)")
  echo "    ${n}: ${metric}"
done

ok "DONE. Quota raised to ${QUOTA_BYTES} bytes (= $((QUOTA_BYTES / 1024 / 1024)) MiB) on all ${#CP_NODES[@]} control-plane node(s)."
