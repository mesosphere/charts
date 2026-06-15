#!/bin/sh
# ============================================================================
# record-current-id.sh   (per-node Job, init container #1)
#
# Records the CURRENT containerID of the etcd container on this node into a
# shared emptyDir BEFORE we touch the static-pod manifest. The verify
# container will read this baseline back and poll the API until the
# containerID changes, proving kubelet has noticed our patch, killed the old
# etcd container, and started a new one.
#
# Without this baseline, we cannot distinguish "etcd never restarted" from
# "etcd already restarted some time ago, possibly into a broken state".
# See README §"The hard parts → Ghost Health Check".
# ============================================================================
set -eu

# Env var injected by the per-node Job spec
# (files/quota-bumper/job-template.yaml). Fail loud if missing.
: "${NODE_NAME:?NODE_NAME must be set by the Job spec env}"

POD_NAME="etcd-${NODE_NAME}"
echo "[record-id] node=${NODE_NAME} pod=${POD_NAME}"

# JSONPath filter selects the etcd container specifically — robust to future
# kubeadm versions that add sidecars to the etcd static pod.
CID=$(kubectl get pod "${POD_NAME}" -n kube-system \
  -o jsonpath='{.status.containerStatuses[?(@.name=="etcd")].containerID}')

if [ -z "${CID}" ]; then
  echo "[record-id] FATAL: could not read containerID for ${POD_NAME}" >&2
  echo "[record-id] dump of pod status:" >&2
  kubectl get pod "${POD_NAME}" -n kube-system -o yaml >&2 || true
  exit 1
fi

printf '%s\n' "${CID}" > /workspace/old-container-id
echo "[record-id] recorded old containerID: ${CID}"
