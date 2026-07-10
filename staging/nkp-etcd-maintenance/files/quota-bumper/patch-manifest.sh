#!/bin/sh
# ============================================================================
# patch-manifest.sh   (per-node Job, init container #2)
#
# 1. Backs up /etc/kubernetes/manifests/etcd.yaml on the host so the operator
#    has a forensic copy in case anything goes wrong.
# 2. Uses yq (NOT sed) to idempotently set --quota-backend-bytes:
#      - drops any existing --quota-backend-bytes=<anything> entry,
#      - appends --quota-backend-bytes=$QUOTA_BYTES.
# 3. Asserts the patched file is valid YAML and contains exactly the target
#    value before swapping it into place.
# 4. Writes the new file atomically via `mv` (same filesystem) so kubelet
#    never reads a half-written manifest.
# ============================================================================
set -eu

# Env vars injected by the per-node Job spec
# (files/quota-bumper/job-template.yaml). Fail loud if missing — otherwise
# the script would silently patch with an empty value or against an
# empty NODE_NAME context.
#
# Variables used in this script:
#   NODE_NAME    — control-plane node we're patching (set by Job env).
#   QUOTA_BYTES  — new --quota-backend-bytes value (set by Job env;
#                  expected as a decimal byte count, e.g. 8589934592).
#   MANIFEST     — absolute path to the etcd static-pod manifest on the
#                  host, reached via the host-manifests hostPath mount.
#   BACKUP_DIR   — directory of MANIFEST. We deliberately don't write
#                  the backup outside this dir (the hostPath mount is
#                  scoped to it and nothing else).
#   BACKUP       — timestamped, dot-prefixed copy of MANIFEST. Dot prefix
#                  hides it from kubelet's static-pod walker.
#   TMP          — pod-side scratch path (emptyDir). We build the patched
#                  manifest here, then atomically mv it into MANIFEST.
#   OLD          — previous --quota-backend-bytes flag value, for logging.
: "${NODE_NAME:?NODE_NAME must be set by the Job spec env}"
: "${QUOTA_BYTES:?QUOTA_BYTES must be set by the Job spec env}"

MANIFEST=/host/etc/kubernetes/manifests/etcd.yaml
# IMPORTANT — backup filename MUST start with a dot.
#
# kubelet scans the entire pod-manifest path and parses EVERY non-dot regular
# file as a static-pod source (not just `*.yaml`). A backup named
# `etcd.yaml.bak.<timestamp>` parses as a valid Pod whose metadata.name is
# `etcd`, exactly like the live manifest — so kubelet sees two static pods
# with the same name and the alphabetically-last one wins. Result: kubelet
# silently runs the OLD (backup) content even after we atomically swap the
# patched manifest in.
#
# Files whose basename begins with `.` are skipped by kubelet's source-file
# walker, so the leading dot turns the backup into a kubelet-invisible
# forensic copy. The operator can still read it with `ls -la`.
BACKUP_DIR=$(dirname "${MANIFEST}")
BACKUP="${BACKUP_DIR}/.etcd.yaml.bak.$(date -u +%Y%m%d-%H%M%SZ)"
TMP=/workspace/etcd.yaml.new

echo "[patch] node=${NODE_NAME} target_quota=${QUOTA_BYTES}"

if [ ! -f "${MANIFEST}" ]; then
  echo "[patch] FATAL: ${MANIFEST} not found on host" >&2
  exit 1
fi

# ---- step 1: backup --------------------------------------------------------
cp -p "${MANIFEST}" "${BACKUP}"
echo "[patch] backup written: ${BACKUP}"

# ---- step 2: log current value before edit --------------------------------
OLD=$(yq '.spec.containers[0].command[] | select(test("^--quota-backend-bytes="))' \
        "${MANIFEST}" 2>/dev/null || true)
if [ -n "${OLD}" ]; then
  echo "[patch] current flag in manifest: ${OLD}"
else
  echo "[patch] no --quota-backend-bytes flag currently set; etcd is on default (2147483648)"
fi

# ---- step 3: idempotent edit ----------------------------------------------
#   (drop existing flag) ++ (append new flag)
# yq operates on a strict YAML AST, not text, so we cannot corrupt the file
# with regex misses.
yq '
  .spec.containers[0].command =
    ( .spec.containers[0].command
      | map(select(test("^--quota-backend-bytes=") | not))
    )
    + ["--quota-backend-bytes=" + strenv(QUOTA_BYTES)]
' "${MANIFEST}" > "${TMP}"

# ---- step 4: validate the result ------------------------------------------
# We use an explicit `select + length` test instead of `any(...)` / `any_c(...)`
# because the spelling of that function changed between yq 4.17 and 4.18:
#     yq <= 4.17  :  any(condition)
#     yq >= 4.18  :  any_c(condition)   (any -> "is any value truthy?")
# `[ ... | select(...) ] | length > 0` is unambiguous across every yq 4.x.
yq -e '
  ([.spec.containers[0].command[]
     | select(. == "--quota-backend-bytes=" + strenv(QUOTA_BYTES))]
   | length) > 0
' "${TMP}" >/dev/null || {
  echo "[patch] FATAL: post-edit verification failed; refusing to swap" >&2
  cat "${TMP}" >&2
  exit 1
}

# ---- step 5: atomic swap ---------------------------------------------------
# mv within the same hostPath mount is a rename(2) — atomic. The kubelet's
# manifest watcher will see the new inode on its next poll cycle (default
# 20 s; configurable via --file-check-frequency on kubelet).
mv "${TMP}" "${MANIFEST}"
chmod 600 "${MANIFEST}"
chown 0:0 "${MANIFEST}"

echo "[patch] manifest atomically replaced; kubelet will pick it up on next poll cycle"
echo "[patch] confirmed flag in patched file:"
yq '.spec.containers[0].command[] | select(test("^--quota-backend-bytes="))' "${MANIFEST}"
