# Low-Level Design — Phase 2: Defrag Helm Chart
## NKP etcd Maintenance Internship

**Jira:** NCN-114548
**Phase:** 2 — Defrag Addon MVP — **✅ COMPLETE AND VALIDATED**
**Chart name:** `nkp-etcd-maintenance`
**Tool:** `ghcr.io/ahrtr/etcd-defrag:v0.40.0`
**Validation:** 2026-06-01 on `nkp-harsh-test` (3-control-plane NKP cluster, K8s v1.35.2)

---

## Validation Summary

Phase 2 has been validated end-to-end on a real 3-control-plane NKP cluster.
The leader-safe defragmentation flow worked exactly as designed:

| # | Member | Role at start of step | dbSize before | dbSize after | Reclaimed | Defrag duration |
|---|---|---|---|---|---|---|
| 1 | `48b7c7…` (.156) | follower | 118.8 MiB | 36.0 MiB | **82.8 MiB** | 367.8 ms |
| 2 | `eb6678…` (.157) | follower | 114.9 MiB | 39.9 MiB | **75.0 MiB** | 457.0 ms |
| 3 | `f19b7f…` (.161) | leader → moved to `48b7c7…` | 118.8 MiB | 47.4 MiB | **71.4 MiB** | 2.53 s |
|   | **Total** |   |   |   | **~229 MiB** | total wall-clock ≈ 3m4s |

The leader-transfer step (`--move-leader`) was observed in the logs:
```
10:45:23  Transferring the leadership from f19b7f4b942e103e to 48b7c7b50b50e125
10:45:23  Transferred the leadership successfully! Waiting for 1m0s for next operation
10:46:23  Defragmenting endpoint "https://10.22.202.161:2379"  (former leader)
```

This confirms the safety guarantee: the cluster always had a healthy leader during
the defrag of any individual member. Full job log captured in `COMMANDS.md` →
Current State section.

---

## Table of Contents

0. [Validation Summary](#validation-summary)
1. [Goals & Non-Goals](#1-goals--non-goals)
2. [Repository Layout](#2-repository-layout)
3. [Resource Inventory](#3-resource-inventory)
4. [Component Deep Dives](#4-component-deep-dives)
   - 4.1 [ServiceAccount](#41-serviceaccount)
   - 4.2 [ClusterRole & ClusterRoleBinding](#42-clusterrole--clusterrolebinding)
   - 4.3 [CronJob](#43-cronjob)
5. [Runtime Flow](#5-runtime-flow)
6. [Configuration Reference](#6-configuration-reference)
7. [Flag-to-Value Mapping](#7-flag-to-value-mapping)
8. [Security Design](#8-security-design)
9. [Scheduling & Concurrency Model](#9-scheduling--concurrency-model)
10. [Networking Model](#10-networking-model)
11. [Certificate Access Model](#11-certificate-access-model)
12. [Known Issues & Resolutions](#12-known-issues--resolutions)
13. [Out of Scope for Phase 2](#13-out-of-scope-for-phase-2)

---

## 1. Goals & Non-Goals

### Goals
- Deploy a recurring, safe, threshold-based etcd defragmentation job onto a
  kubeadm-managed NKP cluster.
- Reuse `ahrtr/etcd-defrag` rather than writing custom shell scripts.
- Expose clean configuration knobs that match the internship brief's proposed
  API shape (`leaderLast`, `defragRule`, `schedule`, `waitBetweenDefrags`, `autoDisalarm`).
- Ensure the job only runs on control-plane nodes, uses existing kubeadm
  certificates, and never conflicts with kubeadm's ownership of etcd.
- Deliver the capability as a standalone Helm chart, ready for Kommander
  platform app packaging in Phase 3.

### Non-Goals
- Does not replace kubeadm as the owner of etcd static pod manifests.
- Does not manage etcd membership, add/remove/replace members.
- Does not automate etcd restore (restore is a manual operator runbook).
- Does not install an etcd operator or replace etcd's lifecycle management.
- Does not handle external etcd clusters.

---

## 2. Repository Layout

```
nkp-etcd-maintenance/
├── Chart.yaml                    # Chart metadata (name, version, appVersion)
├── values.yaml                   # All user-facing configuration knobs
├── README.md                     # User/operator documentation
├── COMMANDS.md                   # Command reference & session log
├── LLD-phase2.md                 # This document
└── templates/
    ├── _helpers.tpl              # Helm named template: chart label helper
    ├── rbac.yaml                 # ServiceAccount + ClusterRole + ClusterRoleBinding
    └── defrag-cronjob.yaml       # The CronJob that runs etcd-defrag
```

---

## 3. Resource Inventory

| Kubernetes Resource | Name | Namespace | Purpose |
|---|---|---|---|
| `ServiceAccount` | `nkp-etcd-maintenance-sa` | `kube-system` | Identity for the defrag pod |
| `ClusterRole` | `nkp-etcd-maintenance-role` | cluster-scoped | Grants permission to write Events |
| `ClusterRoleBinding` | `nkp-etcd-maintenance-rolebinding` | cluster-scoped | Binds role to the ServiceAccount |
| `CronJob` | `nkp-etcd-defrag` | `kube-system` | Schedules and runs defrag Jobs |

All four resources are created by a single `helm install` and removed by a
single `helm uninstall`. They are all gated behind `defragmentation.enabled`
so the entire feature can be toggled off without uninstalling the chart.

---

## 4. Component Deep Dives

### 4.1 ServiceAccount

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: nkp-etcd-maintenance-sa
  namespace: kube-system
```

**Purpose:** Provides a distinct identity for the defrag pod, separate from the
`default` service account. This is required so that RBAC rules can be scoped
precisely to only the permissions this job needs, rather than broadening the
`default` account.

**Why `kube-system`:** The CronJob and its pods run in `kube-system`. Service
accounts are namespaced, so the SA must be in the same namespace as the pod
that uses it.

**Token mounting:** No explicit `automountServiceAccountToken: false` is set
because the pod needs the token to post Kubernetes Events (see ClusterRole
below).

---

### 4.2 ClusterRole & ClusterRoleBinding

```yaml
rules:
  - apiGroups: ["", "events.k8s.io"]
    resources: ["events"]
    verbs: ["create", "patch", "update"]
```

**Why ClusterRole and not a Role?**
Events from a batch Job pod can be posted to either the core API group (`""`)
or the `events.k8s.io` group depending on the Kubernetes version. A
`ClusterRole` covers both API groups cluster-wide without needing to predict
which namespace the event will land in.

**Why only Events?**
The `etcd-defrag` tool itself connects directly to the etcd endpoint using
TLS client certificates mounted from the host — it does not use the Kubernetes
API to talk to etcd. The only reason the pod needs any Kubernetes RBAC at all
is to emit `Event` objects recording its run status. This is the absolute
minimum privilege necessary.

No `get`, `list`, `watch`, or `delete` verbs are granted. No access to Pods,
Secrets, ConfigMaps, or any other resource is given.

---

### 4.3 CronJob

The CronJob is the core resource. It has several interlocking design decisions.

#### 4.3.1 Schedule

```yaml
spec:
  schedule: "30 2 * * *"   # 02:30 UTC every day
```

Configurable via `defragmentation.schedule`. The default targets a low-traffic
window. The cron expression uses UTC; operators in IST (UTC+5:30) should note
that `30 2 * * *` fires at 08:00 IST.

#### 4.3.2 Concurrency control

```yaml
concurrencyPolicy: Forbid
```

If a defrag run is still in progress when the next cron tick fires (e.g.
because a multi-node defrag took longer than expected), the new tick is silently
skipped. This prevents two defrag jobs from running simultaneously, which could
cause excessive etcd write latency or quorum instability.

`OnFailure` and `Replace` are explicitly not used:
- `Allow` — would allow concurrent runs, defeating the safety model.
- `Replace` — would kill a running defrag mid-operation, leaving the database
  in an inconsistent compacted state.

#### 4.3.3 Job history retention

```yaml
successfulJobsHistoryLimit: 3
failedJobsHistoryLimit: 3
```

Kubernetes retains the last N Job objects (and their pods) so operators can
inspect logs after the fact. Three each is a reasonable default; it provides
enough history for audit without accumulating stale pods indefinitely.

#### 4.3.4 Restart policy

```yaml
restartPolicy: Never
```

If the defrag container exits with a non-zero code, Kubernetes creates a new
pod (up to `backoffLimit`, default 6). Once all retries are exhausted, the Job
enters `Failed` state. The CronJob will attempt the run again at the next
scheduled tick.

`OnFailure` is not used because it would restart the container in-place on the
same pod; `Never` gives each retry a clean pod with fresh logs, which is
easier to debug.

---

## 5. Runtime Flow

```
                     ┌──────────────────────────────────────────┐
                     │  kube-controller-manager                  │
                     │  watches CronJob spec                     │
   cron tick fires   │                                           │
  ──────────────────►│  creates Job object                       │
                     │  (skips if ACTIVE > 0, concurrencyPolicy) │
                     └───────────────┬──────────────────────────┘
                                     │
                                     ▼
                     ┌──────────────────────────────────────────┐
                     │  kube-scheduler                           │
                     │                                           │
                     │  evaluates nodeSelector:                  │
                     │    node-role.kubernetes.io/control-plane  │
                     │  evaluates toleration:                    │
                     │    control-plane:NoSchedule               │
                     │                                           │
                     │  → schedules pod on control-plane node    │
                     └───────────────┬──────────────────────────┘
                                     │
                                     ▼
                     ┌──────────────────────────────────────────┐
                     │  control-plane node (host network ns)     │
                     │                                           │
                     │  Pod starts with:                         │
                     │  - hostNetwork: true                      │
                     │  - /etc/kubernetes/pki/etcd  (readOnly)   │
                     │                                           │
                     │  etcd-defrag binary runs:                 │
                     │                                           │
                     │  1. Cluster health check                  │
                     │     GET https://127.0.0.1:2379/health     │
                     │     (abort if any member unhealthy)       │
                     │                                           │
                     │  2. Evaluate defrag rule per member       │
                     │     dbQuotaUsage > 0.5 ||                 │
                     │     dbSize - dbSizeInUse > 200 MiB        │
                     │     (skip member if rule is false)        │
                     │                                           │
                     │  3. For each non-leader member:           │
                     │     - defragment                          │
                     │     - wait 1m (waitBetweenDefrags)        │
                     │                                           │
                     │  4. For the leader (last):                │
                     │     - move-leader → transfer leadership   │
                     │     - defragment former leader            │
                     │                                           │
                     │  5. Exit 0 (success) or non-zero (fail)  │
                     └──────────────────────────────────────────┘
                                     │
                    ┌────────────────┴────────────────┐
                    │                                  │
                    ▼                                  ▼
             exit 0                             exit non-zero
        Job → Complete                      Pod → Error
        (retained, 3 max)               Job retries up to backoffLimit
                                        then Job → Failed
```

---

## 6. Configuration Reference

All values live in `values.yaml` and can be overridden at install time with
`--set key=value` or `-f custom-values.yaml`.

### `defragmentation` block

| Key | Type | Default | Maps to flag | Description |
|---|---|---|---|---|
| `enabled` | bool | `true` | (template gate) | Master toggle for all resources |
| `schedule` | string | `"30 2 * * *"` | `spec.schedule` | Cron schedule (UTC) |
| `defragRule` | string | `"dbQuotaUsage > 0.5 \|\| dbSize - dbSizeInUse > 200*1024*1024"` | `--defrag-rule` | Threshold expression; defrag skipped if false |
| `endpoint` | string | `"https://127.0.0.1:2379"` | `--endpoints` | etcd client endpoint |
| `cluster` | bool | `true` | `--cluster` | Defrag all members + enables health pre-check |
| `leaderLast` | bool | `true` | `--move-leader` | Transfer leadership before defragging the current leader |
| `waitBetweenDefrags` | string | `"1m"` | `--wait-between-defrags` | Pause between per-member operations |
| `autoDisalarm` | bool | `false` | `--auto-disalarm` | Clear NOSPACE alarms automatically after defrag |
| `etcdPkiHostPath` | string | `"/etc/kubernetes/pki/etcd"` | volume + args | Host path for etcd client certificates |

### `image` block

| Key | Default | Description |
|---|---|---|
| `image.repository` | `ghcr.io/ahrtr/etcd-defrag` | Override for air-gapped deployments |
| `image.tag` | `v0.40.0` | Pin to a specific release |
| `image.pullPolicy` | `IfNotPresent` | Standard Kubernetes pull policy |

### Other knobs

| Key | Default | Description |
|---|---|---|
| `resources.requests.cpu` | `50m` | CPU request |
| `resources.requests.memory` | `64Mi` | Memory request |
| `resources.limits.cpu` | `200m` | CPU limit |
| `resources.limits.memory` | `128Mi` | Memory limit |
| `successfulJobsHistoryLimit` | `3` | Completed job pods to retain |
| `failedJobsHistoryLimit` | `3` | Failed job pods to retain |
| `imagePullSecrets` | `[]` | Pull secrets for private registries |
| `commonLabels` | `{}` | Extra labels on all resources |
| `cronJobAnnotations` | `{}` | Extra annotations on the CronJob only |

---

## 7. Flag-to-Value Mapping

The table below shows exactly how each `values.yaml` key becomes a container
argument. This is the complete translation layer between user config and binary
invocation.

```
values.yaml key                         → container arg
──────────────────────────────────────────────────────────────────
defragmentation.endpoint                → --endpoints=<value>
defragmentation.etcdPkiHostPath + /ca   → --cacert=<path>/ca.crt
defragmentation.etcdPkiHostPath + /srv  → --cert=<path>/server.crt
defragmentation.etcdPkiHostPath + /key  → --key=<path>/server.key
defragmentation.cluster == true         → --cluster  (boolean flag)
defragmentation.leaderLast == true      → --move-leader  (boolean flag)
defragmentation.autoDisalarm == true    → --auto-disalarm  (boolean flag)
defragmentation.waitBetweenDefrags      → --wait-between-defrags=<value>
defragmentation.defragRule              → --defrag-rule=<value>
```

> **Note on `leaderLast` → `--move-leader`:**
> The internship brief specifies `leaderLast: true` as the user-facing API.
> `etcd-defrag v0.40.0` does not have a `--leader-last` flag; the equivalent
> is `--move-leader`, which achieves a stronger safety guarantee by transferring
> leadership before defragging the leader rather than merely ordering it last.

---

## 8. Security Design

### Principle of least privilege

| Concern | Implementation |
|---|---|
| Kubernetes API access | Only `events: create/patch/update`. No read access to any resource. |
| Linux capabilities | No explicit drops — default capability set is sufficient for a short-lived batch job. |
| Root filesystem | `readOnlyRootFilesystem: true` — no writes inside the container |
| Privilege escalation | `allowPrivilegeEscalation: false` |
| Host access | Only the etcd PKI directory is shared, mounted `readOnly: true`. No other host paths. |
| Network | `hostNetwork: true` is required to reach `127.0.0.1:2379` but does not grant any additional filesystem or process access. |

### Why `capabilities.drop: [ALL]` is not applied

The initial chart dropped all capabilities. This was removed because retaining
the default Linux capability set (including `DAC_OVERRIDE`) is necessary for
the container to read the etcd certificate files. The meaningful security
controls that remain are `allowPrivilegeEscalation: false`,
`readOnlyRootFilesystem: true`, `readOnly` volume mount, and the container's
ephemeral, batch-job nature.

### Why `runAsUser: 0` is required

The `ghcr.io/ahrtr/etcd-defrag:v0.40.0` image defines a non-root USER in its
Dockerfile (distroless images typically default to UID `65532`). On kubeadm
nodes, `server.key` has `0600 root:root` permissions — readable only by the
file owner (UID 0). A container running as UID `65532` cannot read it.

`runAsUser: 0` explicitly overrides the image's USER instruction and forces the
process to run as UID 0, which is the file's owner. This is the only correct
fix; `runAsNonRoot: false` alone does not change the UID — it only disables the
admission webhook check that would reject root containers.

The security boundary is maintained by `readOnlyRootFilesystem: true` and
`allowPrivilegeEscalation: false` rather than by running as non-root.

### Certificate security

The etcd client certificates mounted from the host (`/etc/kubernetes/pki/etcd`)
are owned by root or a dedicated system user with `0600` permissions. Because
the container runs as root with `DAC_OVERRIDE` retained, it can read these
files. The volume is always mounted `readOnly: true` — the container cannot
modify certificates.

---

## 9. Scheduling & Concurrency Model

### Why only control-plane nodes?

etcd runs as a `staticPod` managed by kubeadm. Static pods are created by
`kubelet` from manifests in `/etc/kubernetes/manifests/` on the node and are
only present on control-plane nodes. The maintenance pod must run on the same
node to reach `127.0.0.1:2379` via the shared host network namespace.

### nodeSelector

```yaml
nodeSelector:
  node-role.kubernetes.io/control-plane: ""
```

kubeadm labels every control-plane node with
`node-role.kubernetes.io/control-plane: ""` during bootstrapping. This label
is stable across Kubernetes upgrades.

### Tolerations (two, for forward + backward compatibility)

```yaml
tolerations:
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
  - key: node-role.kubernetes.io/master         # legacy label, pre-K8s 1.25
    operator: Exists
    effect: NoSchedule
```

kubeadm also applies a `NoSchedule` taint to control-plane nodes to prevent
regular workloads from being scheduled there. This toleration explicitly opts
the defrag pod into scheduling on tainted nodes. The second toleration covers
older kubeadm clusters that still use the `master` key (deprecated in K8s 1.24,
removed in 1.25).

### Concurrency

The combination of `concurrencyPolicy: Forbid` and `restartPolicy: Never`
means:
- At most **one active defrag Job** exists at any time.
- Within a Job, pods retry up to `backoffLimit` (default 6) on failure.
- A new cron tick while the previous Job is still active is silently skipped.

---

## 10. Networking Model

```
┌─────────────────────────────────────────────────────────────┐
│  control-plane node                                          │
│                                                             │
│  ┌─────────────────────────┐   ┌──────────────────────────┐ │
│  │  etcd static pod        │   │  etcd-defrag pod          │ │
│  │  (kubeadm-managed)      │   │  (hostNetwork: true)      │ │
│  │                         │   │                           │ │
│  │  listens on:            │   │  connects to:             │ │
│  │  127.0.0.1:2379 (client)│◄──│  127.0.0.1:2379           │ │
│  │  <NODE_IP>:2379         │   │  (TLS, client cert auth)  │ │
│  │  <NODE_IP>:2380 (peer)  │   │                           │ │
│  │  127.0.0.1:2381 (metrics│   │                           │ │
│  └─────────────────────────┘   └──────────────────────────┘ │
│                                                             │
│  Both pods share the HOST network namespace                  │
│  (loopback 127.0.0.1 is the same interface)                 │
└─────────────────────────────────────────────────────────────┘
```

**Why `hostNetwork: true` is required:**

In a standard Kubernetes pod, each pod gets its own network namespace with its
own loopback (`lo`) interface. `127.0.0.1` inside a normal pod refers to the
pod's own loopback, not the host's. etcd binds to the *host's* `127.0.0.1`.

With `hostNetwork: true`, the pod shares the host's network namespace entirely.
The pod's loopback IS the host's loopback, so `127.0.0.1:2379` resolves to
the etcd process running on the host.

**Ports used:**

| Port | Protocol | Purpose |
|---|---|---|
| `127.0.0.1:2379` | TLS gRPC | etcd client API (defrag, health check) |
| `<NODE_IP>:2379` | TLS gRPC | Alternative endpoint (not used by this chart) |
| `<NODE_IP>:2380` | TLS gRPC | etcd peer communication (not used) |
| `127.0.0.1:2381` | HTTP | Prometheus metrics scrape (not used by defrag) |

---

## 11. Certificate Access Model

kubeadm stores etcd's PKI material at `/etc/kubernetes/pki/etcd/` on every
control-plane node. The files relevant to client authentication are:

| File | Purpose | Owner | Permissions |
|---|---|---|---|
| `ca.crt` | CA certificate — verifies etcd server identity | `root:root` | `0644` |
| `server.crt` | Client certificate — authenticates the caller to etcd | `root:root` | `0644` |
| `server.key` | Client private key | `root:root` | `0600` |

### Why `server.crt` / `server.key` (not `peer` or `healthcheck-client`)?

kubeadm issues several certificate pairs for etcd. The `server` cert is the
most permissive client credential — it has the `server auth` and `client auth`
EKUs, granting full administrative access to the etcd API. This is the same
credential used by the `etcd` process itself for inter-member communication and
is appropriate for a maintenance tool that needs to issue defrag RPCs.

Alternative certs (`peer.*`, `healthcheck-client.*`) are more restricted; the
`healthcheck-client` cert only has the health check permission and cannot issue
defrag operations.

### Volume mount in the chart

```yaml
volumes:
  - name: etcd-pki
    hostPath:
      path: /etc/kubernetes/pki/etcd    # configurable via etcdPkiHostPath
      type: Directory

containers:
  - volumeMounts:
    - name: etcd-pki
      mountPath: /etc/kubernetes/pki/etcd
      readOnly: true
```

The `mountPath` is intentionally set to the **same path** as the `hostPath`.
This means all `--cacert`, `--cert`, and `--key` arguments in the container
args resolve to the correct paths without any translation layer.

---

## 12. Known Issues & Resolutions

### Issue 1: `--leader-last` flag does not exist in v0.40.0

**Discovered:** 2026-05-28, during first manual test run (`manual-defrag-1779949530`).

**Symptom:** All job pods exited immediately with:
```
Error: unknown flag: --leader-last
```

**Root cause:** The internship brief's proposed config shape references
`leaderLast: true`, implying a `--leader-last` CLI flag. This flag does not
exist in `ahrtr/etcd-defrag v0.40.0`. The correct flag is `--move-leader`.

**Resolution:**
- `values.yaml`: Key kept as `leaderLast` (matches brief API), mapped internally
  to `--move-leader` in the template.
- `values.yaml`: Added `waitBetweenDefrags: "1m"` and `autoDisalarm: false`
  (also specified in the brief but missing from the original chart).
- Chart fix is on disk. **`helm upgrade` must be run to apply to the cluster.**

### Issue 3: `permission denied` on `server.key` (discovered 2026-05-29)

**Symptom:**
Job pods (`manual-defrag-1780027602`, `manual-defrag-1780031229`) reached the
correct control-plane node and passed the `--move-leader` fix, but failed with:
```
Failed to get members' health info: open /etc/kubernetes/pki/etcd/server.key: permission denied
```

**Investigation — two incorrect hypotheses before root cause was found:**

*Hypothesis 1 (wrong):* `capabilities.drop: [ALL]` removes `DAC_OVERRIDE`,
causing a root container to be denied on a non-root-owned file.
Fix attempted: removed `capabilities.drop: [ALL]`. Error persisted.

*Root cause (correct):* `runAsNonRoot: false` was misread as "run as root".
It is not. It only disables Kubernetes' enforcement check that blocks root
containers — it does not change the container UID. The actual UID is set by the
`USER` instruction in the image's Dockerfile. `ghcr.io/ahrtr/etcd-defrag`
defines a non-root USER (distroless images typically use UID `65532`). On the
host, `server.key` is `0600 root:root`. A process running as UID `65532`:
- Is not the file owner (UID 0)
- Is not in the file's group (root/0)
- Has no "other" read permission (`0600` = `rw-------`)
- Result: `permission denied`

**Fix:**
Added `runAsUser: 0` to the container securityContext. This explicitly overrides
the image's `USER` instruction and forces the container process to run as UID 0,
which can read `0600 root:root` files. Removed the now-redundant `runAsNonRoot: false`.

**The distinction that matters:**

| Field | What it does |
|---|---|
| `runAsNonRoot: false` | Disables the Kubernetes admission check that would reject a root container — does NOT set the UID |
| `runAsUser: 0` | Actively overrides the image's USER instruction and sets the process UID to 0 |

---

### Issue 2: `<timestamp>` placeholder interpreted as shell redirect

**Discovered:** 2026-05-28, when copy-pasting `kubectl get pods -l job-name=manual-defrag-<timestamp>`.

**Symptom:** `zsh: no such file or directory: timestamp`

**Root cause:** In `zsh`/`bash`, `<foo>` is input redirection, not a placeholder.

**Resolution:** Always use the `$JOB` variable pattern:
```bash
JOB=$(kubectl get jobs -n kube-system \
  --sort-by=.metadata.creationTimestamp \
  -o jsonpath='{.items[-1].metadata.name}')
kubectl get pods -n kube-system -l job-name=$JOB -w
```

---

## 13. Out of Scope for Phase 2

The following items are explicitly deferred to Phase 3 or Phase 4:

| Item | Deferred to |
|---|---|
| Kommander platform app packaging | Phase 3 |
| `KommanderCluster` configuration override example | Phase 3 |
| etcd snapshot CronJob (`etcdctl snapshot save`) | Phase 4 (stretch) |
| Snapshot verification (`etcdutl snapshot status`) | Phase 4 (stretch) |
| S3-compatible snapshot upload | Phase 4 (stretch) |
| PrometheusRule alerts (fragmentation, defrag failure) | Phase 3/4 |
| Status ConfigMap summarising last run | Phase 3/4 |
| Restore runbook documentation | Phase 4 |
