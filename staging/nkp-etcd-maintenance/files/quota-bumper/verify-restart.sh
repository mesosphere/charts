#!/bin/sh
# ============================================================================
# verify-restart.sh   (per-node Job, main container)
#
# The "Ghost Health Check" mitigation. Each step has a strict deadline; the
# Job fails (and the orchestrator aborts the rollout) if any step exceeds it.
#
#   step 1 — wait for kubelet to swap the container ID
#   step 2 — wait for the new pod to become Ready
#   step 3 — run etcdctl endpoint health LOCALLY on the new pod
#   step 4 — run etcdctl endpoint health --cluster (quorum-wide)
#   step 5 — read the spec back, assert flag is applied
# ============================================================================
set -eu

# Env vars are injected by the per-node Job spec (see
# files/quota-bumper/job-template.yaml). Assert they're set explicitly so the
# failure mode of running this script in any other context is loud, not
# a silent `etcd-` (empty NODE_NAME) pod lookup. Also satisfies shellcheck
# SC2153 — which otherwise can't see the Kubernetes-side assignment.
: "${NODE_NAME:?NODE_NAME must be set by the Job spec env}"

# Variables used in this script:
#   NODE_NAME                — control-plane node we're verifying.
#   POD_NAME                 — derived: kubeadm names etcd's static
#                              pod "etcd-<node>".
#   OLD_CID                  — pre-patch containerID, written by
#                              record-current-id.sh into the shared
#                              emptyDir.
#   VERIFY_TIMEOUT_SECONDS   — wall-clock budget for the whole script
#                              (env, default 360s).
#   DEADLINE                 — absolute epoch second at which we give up
#                              and exit FATAL.
#   NEW_CID                  — current containerID after the patch; must
#                              differ from OLD_CID for step 1 to pass.
#   READY                    — kubelet-reported readiness flag (string
#                              "true"/"false").
#   APPLIED                  — the --quota-backend-bytes line read back
#                              from the *running* pod spec for step 5.
#   QUOTA_BYTES              — expected new value (Job env). Used to
#                              assert APPLIED matches.
POD_NAME="etcd-${NODE_NAME}"
OLD_CID=$(cat /workspace/old-container-id)
# Total wall-clock budget for the whole verify phase. `${VAR:-default}` =
# use VAR if set & non-empty, else fall back to default.
DEADLINE=$(( $(date +%s) + ${VERIFY_TIMEOUT_SECONDS:-360} ))

echo "[verify] node=${NODE_NAME} pod=${POD_NAME}"
echo "[verify] old containerID = ${OLD_CID}"

# ----------- helpers --------------------------------------------------------
# `now`        : current epoch seconds (UTC, monotonic-ish).
# `remaining`  : seconds left until DEADLINE (negative once expired).
# `check_deadline`: bail out immediately if we've overshot DEADLINE.
#                   Takes a single arg = human-readable step label,
#                   used only in the FATAL log line.
# `etcdctl_in_pod`: exec etcdctl inside the etcd pod with the in-pod PKI.
#                   We deliberately don't ship etcdctl in our Job image;
#                   reusing the one inside etcd guarantees client/server
#                   protocol parity.
now()              { date +%s; }
remaining()        { echo $(( DEADLINE - $(now) )); }
check_deadline()   {
  if [ "$(now)" -ge "${DEADLINE}" ]; then
    echo "[verify] FATAL: hit ${VERIFY_TIMEOUT_SECONDS:-360}s timeout at step: $1" >&2
    kubectl describe pod "${POD_NAME}" -n kube-system 2>&1 | tail -40 >&2 || true
    exit 1
  fi
}
etcdctl_in_pod()   {
  kubectl exec "${POD_NAME}" -n kube-system -- etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    --command-timeout=5s \
    "$@"
}

# ----------- step 1: containerID change ------------------------------------
# This is THE step that defeats the Ghost Health Check race. We do NOT
# proceed until the kernel has replaced the etcd container — at which point
# the OLD etcd is no longer listening on 127.0.0.1:2379, so the next
# etcdctl call cannot accidentally talk to it.
echo "[verify] step 1: waiting for kubelet to swap the etcd container..."
while :; do
  NEW_CID=$(kubectl get pod "${POD_NAME}" -n kube-system \
    -o jsonpath='{.status.containerStatuses[?(@.name=="etcd")].containerID}' 2>/dev/null || echo "")
  if [ -n "${NEW_CID}" ] && [ "${NEW_CID}" != "${OLD_CID}" ]; then
    echo "[verify] step 1: container restart detected (new containerID=${NEW_CID})"
    break
  fi
  check_deadline "containerID change ($(remaining)s left)"
  sleep 3
done

# ----------- step 2: pod Ready ---------------------------------------------
# containerID changed implies kubelet started a new container, but not that
# etcd has finished its boot/leader-catch-up. We additionally require the
# kubelet-reported readiness gate (which depends on the static pod's
# liveness/readiness probes).
echo "[verify] step 2: waiting for ${POD_NAME} to report Ready..."
while :; do
  READY=$(kubectl get pod "${POD_NAME}" -n kube-system \
    -o jsonpath='{.status.containerStatuses[?(@.name=="etcd")].ready}' 2>/dev/null || echo "false")
  if [ "${READY}" = "true" ]; then
    echo "[verify] step 2: ${POD_NAME} Ready=true"
    break
  fi
  check_deadline "pod Ready=true ($(remaining)s left)"
  sleep 3
done

# ----------- step 3: node-local health -------------------------------------
echo "[verify] step 3: etcdctl endpoint health (local) ..."
n=0
until etcdctl_in_pod endpoint health; do
  n=$((n+1))
  if [ "${n}" -ge 5 ] || [ "$(now)" -ge "${DEADLINE}" ]; then
    echo "[verify] FATAL: local endpoint health failed ${n} time(s)" >&2
    exit 1
  fi
  echo "[verify] step 3: attempt ${n} failed, retrying in 5s ..."
  sleep 5
done

# ----------- step 4: cluster-wide health -----------------------------------
# Confirms quorum is fully reformed — this is the gate the orchestrator
# relies on before moving to the next node.
echo "[verify] step 4: etcdctl endpoint health --cluster ..."
n=0
until etcdctl_in_pod endpoint health --cluster; do
  n=$((n+1))
  if [ "${n}" -ge 10 ] || [ "$(now)" -ge "${DEADLINE}" ]; then
    echo "[verify] FATAL: cluster-wide endpoint health failed ${n} time(s)" >&2
    exit 1
  fi
  echo "[verify] step 4: attempt ${n} failed, retrying in 5s ..."
  sleep 5
done

# ----------- step 5: assert flag applied -----------------------------------
# Read the *running* pod's spec back from the API and confirm the new flag
# is present. `{range …}{@}{"\n"}{end}` is the jsonpath trick for emitting
# one element per line so grep can match a whole flag. If grep finds
# nothing the `|| echo "MISSING"` keeps APPLIED non-empty so the equality
# check below fires the right error message.
APPLIED=$(kubectl get pod "${POD_NAME}" -n kube-system \
  -o jsonpath='{range .spec.containers[?(@.name=="etcd")].command[*]}{@}{"\n"}{end}' \
  | grep '^--quota-backend-bytes=' || echo "MISSING")
if [ "${APPLIED}" != "--quota-backend-bytes=${QUOTA_BYTES}" ]; then
  echo "[verify] FATAL: running pod spec is not what we patched." >&2
  echo "[verify] expected: --quota-backend-bytes=${QUOTA_BYTES}" >&2
  echo "[verify] got:      ${APPLIED}" >&2
  exit 1
fi
echo "[verify] step 5: confirmed running pod spec carries ${APPLIED}"

echo "[verify] SUCCESS — node ${NODE_NAME} fully patched and quorum healthy"
