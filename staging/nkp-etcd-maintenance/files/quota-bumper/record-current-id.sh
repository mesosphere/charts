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
# `set -e` aborts on first error; `set -u` treats unset vars as errors.
# Combined: the script either runs cleanly to the end, or exits with a
# non-zero status that the Job controller marks Failed.
set -eu

# Env var injected by the per-node Job spec
# (files/quota-bumper/job-template.yaml). Fail loud if missing.
#
# Variables used in this script:
#   NODE_NAME — control-plane node we're bumping. Set in the Job env.
#   POD_NAME  — derived: kubeadm names the etcd static pod "etcd-<node>".
#   CID       — the etcd container's containerID (CRI string like
#               "containerd://abc123…"). The "baseline" we hand to the
#               verify container.
: "${NODE_NAME:?NODE_NAME must be set by the Job spec env}"

POD_NAME="etcd-${NODE_NAME}"
echo "[record-id] node=${NODE_NAME} pod=${POD_NAME}"

# JSONPath filter selects the etcd container specifically — robust to future
# kubeadm versions that add sidecars to the etcd static pod.
CID=$(kubectl get pod "${POD_NAME}" -n kube-system \
  -o jsonpath='{.status.containerStatuses[?(@.name=="etcd")].containerID}')

# Empty CID means the etcd container is not yet running / reporting status.
# That's a hard failure here — we can't bump quota on a sick cluster.
if [ -z "${CID}" ]; then
  echo "[record-id] FATAL: could not read containerID for ${POD_NAME}" >&2
  echo "[record-id] dump of pod status:" >&2
  kubectl get pod "${POD_NAME}" -n kube-system -o yaml >&2 || true
  exit 1
fi

# `printf '%s\n'` is safer than `echo` for arbitrary strings (echo
# would interpret leading "-" args). The file is read back by
# verify-restart.sh from the shared emptyDir.
printf '%s\n' "${CID}" > /workspace/old-container-id
echo "[record-id] recorded old containerID: ${CID}"
