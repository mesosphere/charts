# nkp-etcd-maintenance

A Helm chart that deploys recurring **etcd maintenance** (defragmentation
and snapshot) CronJobs on kubeadm-managed
[Nutanix Kubernetes Platform (NKP)](https://www.nutanix.com/products/kubernetes-engine)
clusters.

The chart ships three independent, optional features:

### 1. Defragmentation CronJob (default: **on**)
Wraps the open-source [ahrtr/etcd-defrag](https://github.com/ahrtr/etcd-defrag) tool:

- **Leader-last defragmentation** — transfers etcd leadership away before defragging
  the current leader (`--move-leader`), ensuring the cluster always has a healthy
  active leader throughout the maintenance window.
- **Cluster-wide execution** — defragments every member in a single run.
- **Built-in health pre-check** — aborts if the cluster is unhealthy before
  touching any member (automatically enabled when `--cluster` is passed).
- **Rule-based triggering** — defrag is a no-op when the database is already
  healthy, avoiding unnecessary disruption.
- **Configurable wait between members** — pauses between each member's defrag
  so the cluster can stabilise before the next operation.

### 2. Snapshot CronJob (default: **off**, opt-in via `snapshot.enabled=true`)
Captures a verified etcd snapshot and optionally uploads it to S3-compatible storage:

- **Two-init-container architecture** — `etcdctl snapshot save` writes the
  snapshot to a Pod-scoped emptyDir, then `etcdutl snapshot status` verifies
  the file before any upload is attempted.
- **SecretRef-only credentials** — bucket access keys live in a Kubernetes
  Secret referenced by name; they never appear in `values.yaml` or
  catalog overrides.
- **S3-compatible** — works with AWS S3, MinIO, Ceph RGW, and Nutanix Objects
  via the `minio/mc` client (path-style addressing by default).
- **Restore is intentionally manual** — see the [Manual Restore Runbook](#manual-restore-runbook)
  below for the supported recovery procedure. The addon will NEVER auto-restore.

### 3. Observability (default: **on**, capability-gated)
Each maintenance run emits three independent signals — no extra sidecar
containers, no custom event-emission logic:

- **Kubernetes Events** — the native `Job` and `CronJob` controllers emit
  Events (`SuccessfulCreate`, `BackoffLimitExceeded`, `MissingJob`, etc.)
  on every state transition. `kubectl describe job <name>` is the canonical
  inspection surface; see [`COMMANDS.md` §9](./COMMANDS.md#9-observability--inspecting-jobs-and-reading-failures).
- **Clear structured logs** — the snapshot upload script emits logfmt lines
  (`[upload] phase=<name> key=value …`) so failures are greppable; etcdctl
  and etcdutl emit upstream JSON, which is also machine-parseable.
- **PrometheusRule alerts** — 8 alerts (etcd-health × 4, defrag × 2,
  snapshot × 2) shipped in a single `monitoring.coreos.com/v1 PrometheusRule`
  resource. Rendered only when `alerts.enabled=true` (default) **and**
  the cluster has the Prometheus Operator CRD — so the chart is safe to
  ship on bare clusters; the rule materialises automatically the day the
  operator arrives. See [Observability — Events, Logs, Alerts](#observability--events-logs-alerts).

---

## Project Status

| Phase | Status | Notes |
|---|---|---|
| Phase 1: Research & Spike | ✅ Complete | Cluster topology validated. Design note written. |
| Phase 2: Defrag Helm chart (this chart) | ✅ **Complete & validated end-to-end** | 3-member etcd run with leader transfer succeeded on `nkp-harsh-test` (2026-06-01). ~229 MiB reclaimed across the cluster. |
| Phase 3: Kommander catalog application | ✅ **Complete** (pending cluster validation) | Design: [LLD-phase3.md](./LLD-phase3.md). Catalog app shipped to [`nkp-nutanix-product-catalog/applications/nkp-etcd-maintenance/0.3.0`](../nkp-nutanix-product-catalog/applications/nkp-etcd-maintenance/0.3.0/) under the standard Flux/Kustomize pattern. |
| Phase 5: Snapshot MVP | 🟡 **In progress** | Design: [LLD-phase5.md](./LLD-phase5.md). Chart implementation, fail-fast invariants, catalog defaults, and docs done. Pending: live-cluster validation against a real S3 endpoint. |
| Phase Observability | ✅ **Complete** (chart-side; live alert firing pending) | Design: [LLD-phase-observability.md](./LLD-phase-observability.md). Adds `templates/prometheusrule.yaml` with 8 alerts (capability-gated), logfmt upload logs, and the docs sections below: [Default Schedules](#default-schedules), [Enabling and Disabling](#enabling-and-disabling), [Observability — Events, Logs, Alerts](#observability--events-logs-alerts), [Limitations and Non-Goals](#limitations-and-non-goals). |

### Phase 2 validation evidence — 2026-06-01, 3-control-plane NKP cluster

Cluster: `nkp-harsh-test` (NKP v2.18.0-dev.41, Kubernetes v1.35.2)

Members: `48b7c7b50b50e125` (10.22.202.156), `eb6678448f194562` (10.22.202.157),
`f19b7f4b942e103e` (10.22.202.161, original leader).

| Member | Role at start | dbSize before | dbSize after | Reclaimed |
|---|---|---|---|---|
| `48b7c7…` (.156) | follower | 124,596,224 B (118.8 MiB) | 37,789,696 B (36.0 MiB) | **82.8 MiB** |
| `eb6678…` (.157) | follower | 120,553,472 B (114.9 MiB) | 41,865,216 B (39.9 MiB) | **75.0 MiB** |
| `f19b7f…` (.161) | leader → transferred to `48b7c7…` | 124,575,744 B (118.8 MiB) | 49,664,000 B (47.4 MiB) | **71.4 MiB** |
| **Total** | | | | **~229 MiB reclaimed** |

Total job runtime: ~3 minutes 4 seconds (3 defrags + 2 × 1-minute waits + 1 leader transfer).
Cluster availability during defrag: **uninterrupted** — leadership was moved off the
member being defragged before it was touched, so the cluster always had a healthy active leader.

---

## Table of Contents

- [Background](#background)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Uninstallation](#uninstallation)
- [Configuration](#configuration)
- [Default Schedules](#default-schedules)
- [Enabling and Disabling](#enabling-and-disabling)
- [Snapshot CronJob (Phase 5)](#snapshot-cronjob-phase-5)
- [Manual Restore Runbook](#manual-restore-runbook)
- [Observability — Events, Logs, Alerts](#observability--events-logs-alerts)
- [Limitations and Non-Goals](#limitations-and-non-goals)
- [Architecture](#architecture)
- [How etcd-defrag Works: The Algorithm](#how-etcd-defrag-works-the-algorithm)
- [Security Strategy: Defense in Depth](#security-strategy-defense-in-depth)
- [Operational Notes](#operational-notes)
- [Troubleshooting](#troubleshooting)
- [Phase 3 — Kommander Catalog Application](#phase-3--kommander-catalog-application)

## Directory map

```
nkp-etcd-maintenance/
├── Chart.yaml                     ← Helm chart metadata (v0.3.0)
├── values.yaml                    ← Build-time defaults (defrag + snapshot)
├── templates/
│   ├── _helpers.tpl
│   ├── defrag-cronjob.yaml        ← Phase 2 defragmentation CronJob
│   ├── rbac.yaml                  ← shared SA / ClusterRole / RoleBinding
│   ├── snapshot-cronjob.yaml      ← Phase 5 snapshot CronJob (gated on
│   │                                 .Values.snapshot.enabled)
│   └── prometheusrule.yaml        ← Phase Observability: 8 alerts, gated on
│                                     .Values.alerts.enabled AND the
│                                     monitoring.coreos.com/v1 CRD
│
├── README.md                      ← this file
├── COMMANDS.md                    ← every command, every state transition
├── LLD-phase2.md                  ← Phase 2 design + validation evidence
├── LLD-phase3.md                  ← Phase 3 design (catalog app)
├── LLD-phase5.md                  ← Phase 5 design (snapshot MVP)
├── LLD-phase-observability.md     ← Phase Observability design (alerts, logs, Events)
│
└── kommander/                     ← Phase 3 catalog scaffolding
    ├── catalog/0.1.0/
    │   ├── application.yaml       ← Application CR (chart ref)
    │   ├── defaults/cm.yaml       ← Catalog default values (defrag + snapshot)
    │   └── metadata.yaml          ← UI display metadata
    ├── examples/
    │   ├── appdeployment.yaml     ← Opt a cluster in via AppDeployment
    │   └── kommandercluster-override.yaml  ← Declarative attach-time
    └── preflight/
        └── topology-check-job.yaml  ← Pre-install topology validator
```

The "real" catalog deliverable lives in the sibling catalog repository under
[`nkp-nutanix-product-catalog/applications/nkp-etcd-maintenance/`](../nkp-nutanix-product-catalog/applications/nkp-etcd-maintenance/),
which ships **two** versions side by side:

- `0.2.0/` — Phase 3 baseline: defrag-only.
- `0.3.0/` — Phase 5: defrag + opt-in snapshot CronJob (this chart version).

The `kommander/` directory above is the in-workspace design scaffold.

---

## Background

etcd's storage engine (bbolt) never reclaims free pages on its own; deleted keys
leave behind "holes" that accumulate over time. Without periodic defragmentation:

- The on-disk database file grows monotonically even if the logical data shrinks.
- Eventually the file size approaches the configured `--quota-backend-bytes`
  limit, causing etcd to trigger an `NOSPACE` alarm and refuse further writes —
  which will bring the entire Kubernetes control plane to a halt.

Defragmentation compacts the bbolt file, reclaims free pages, and resets the
effective db size. This chart automates that process on a cron schedule with
sensible defaults.

---

## Prerequisites

| Requirement | Details |
|---|---|
| Kubernetes | 1.25+ (kubeadm-managed cluster) |
| Helm | 3.x |
| etcd PKI | kubeadm certs present at `/etc/kubernetes/pki/etcd` on every control-plane node |
| Container runtime | Must support `hostNetwork` pods (standard on all kubeadm distros) |

---

## Installation

### From the local chart directory

```bash
helm upgrade --install nkp-etcd-maintenance ./nkp-etcd-maintenance \
  --namespace kube-system
```

### With a custom schedule

```bash
helm upgrade --install nkp-etcd-maintenance ./nkp-etcd-maintenance \
  --namespace kube-system \
  --set defragmentation.schedule="0 3 * * 0"   # every Sunday at 03:00 UTC
```

### With a custom defrag rule

```bash
helm upgrade --install nkp-etcd-maintenance ./nkp-etcd-maintenance \
  --namespace kube-system \
  --set defragmentation.defragRule="dbQuotaUsage > 0.8"
```

### Dry-run (render manifests without applying)

```bash
helm template nkp-etcd-maintenance ./nkp-etcd-maintenance
```

---

## Uninstallation

```bash
helm uninstall nkp-etcd-maintenance --namespace kube-system
```

> **Note:** The `ClusterRole` and `ClusterRoleBinding` are cluster-scoped and
> will also be removed by `helm uninstall`.

---

## Configuration

All parameters are set in `values.yaml` and can be overridden at install time
with `--set` or `-f custom-values.yaml`.

### `defragmentation`

| Parameter | Default | Description |
|---|---|---|
| `defragmentation.enabled` | `true` | Master toggle. Set to `false` to disable the CronJob without uninstalling the chart. |
| `defragmentation.schedule` | `"30 2 * * *"` | Cron schedule in UTC. Default fires at 02:30 every day. |
| `defragmentation.defragRule` | `"dbQuotaUsage > 0.5 \|\| dbSize - dbSizeInUse > 200*1024*1024"` | Rule evaluated before each defrag. Defrag is skipped when the expression is `false`. See [rule syntax](https://github.com/ahrtr/etcd-defrag#defrag-rule). |
| `defragmentation.endpoint` | `"https://127.0.0.1:2379"` | etcd endpoint. For kubeadm this is always localhost (reached via `hostNetwork`). |
| `defragmentation.cluster` | `true` | Defragment all cluster members, not just the contacted endpoint. Also enables the automatic cluster health pre-check — the run is aborted if any member is unhealthy. |
| `defragmentation.leaderLast` | `true` | Defragment the leader last. Maps to `--move-leader` in etcd-defrag v0.40.0, which transfers leadership away before defragging the current leader — the same safety guarantee as strict "leader-last" ordering. |
| `defragmentation.waitBetweenDefrags` | `"1m"` | Wait duration between consecutive per-member defrag operations. Gives the cluster time to stabilise. Set to `"0s"` to disable. |
| `defragmentation.autoDisalarm` | `false` | Automatically clear `NOSPACE` alarms after a successful defragmentation. Leave `false` to require manual operator review before clearing alarms. |
| `defragmentation.etcdPkiHostPath` | `"/etc/kubernetes/pki/etcd"` | Host path containing the kubeadm etcd PKI files. Mounted read-only into the container. |

### `image`

| Parameter | Default | Description |
|---|---|---|
| `image.repository` | `ghcr.io/ahrtr/etcd-defrag` | Container image repository. Override for air-gapped / private registry deployments. |
| `image.tag` | `v0.40.0` | Image tag. |
| `image.pullPolicy` | `IfNotPresent` | Kubernetes image pull policy. |
| `imagePullSecrets` | `[]` | List of image pull secret names for private registries. |

### `resources`

| Parameter | Default | Description |
|---|---|---|
| `resources.requests.cpu` | `50m` | CPU request for the defrag container. |
| `resources.requests.memory` | `64Mi` | Memory request for the defrag container. |
| `resources.limits.cpu` | `200m` | CPU limit. |
| `resources.limits.memory` | `128Mi` | Memory limit. |

### Misc

| Parameter | Default | Description |
|---|---|---|
| `successfulJobsHistoryLimit` | `3` | Number of completed defrag job pods to retain. (Snapshot has its own `snapshot.successfulJobsHistoryLimit`.) |
| `failedJobsHistoryLimit` | `3` | Number of failed defrag job pods to retain. |
| `commonLabels` | `{}` | Extra labels applied to every resource created by this chart (defrag AND snapshot). |
| `cronJobAnnotations` | `{}` | Extra annotations applied to both CronJob resources. |

### `snapshot` (Phase 5)

| Parameter | Default | Description |
|---|---|---|
| `snapshot.enabled` | `false` | Master toggle for the snapshot CronJob. Defrag CronJob is unaffected. |
| `snapshot.schedule` | `"0 3 * * *"` | Cron schedule in UTC. Default fires daily 30 min after the defrag job. |
| `snapshot.clusterName` | `""` | Cluster name used in the S3 object key. Defaults to the Helm release name when empty. |
| `snapshot.endpoint` | `"https://127.0.0.1:2379"` | etcd client endpoint (reached over host loopback via `hostNetwork`). |
| `snapshot.etcdPkiHostPath` | `"/etc/kubernetes/pki/etcd"` | Host path containing kubeadm etcd certs. Mounted RO into the `take-snapshot` init container only. |
| `snapshot.etcdImage.repository` | `registry.k8s.io/etcd` | Image used by both init containers. Pin to your cluster's etcd minor. |
| `snapshot.etcdImage.tag` | `"3.5.15-0"` | etcd image tag. |
| `snapshot.etcdImage.pullPolicy` | `IfNotPresent` | Pull policy. |
| `snapshot.etcdResources` | (see `values.yaml`) | Per-init-container resource requests/limits. Includes `ephemeral-storage`. |
| `snapshot.successfulJobsHistoryLimit` | `7` | Completed snapshot Job retention. |
| `snapshot.failedJobsHistoryLimit` | `7` | Failed snapshot Job retention. |
| `snapshot.startingDeadlineSeconds` | `300` | Skip a missed cron tick if the controller is more than this many seconds late. |
| `snapshot.ttlSecondsAfterFinished` | `86400` | Garbage-collect finished snapshot Jobs after one day. |

### `snapshot.s3` (Phase 5 — upload, optional)

| Parameter | Default | Description |
|---|---|---|
| `snapshot.s3.enabled` | `false` | If `false`, the snapshot is taken and verified but DISCARDED on Pod termination. |
| `snapshot.s3.endpoint` | `""` | **Required when `s3.enabled=true`.** Full URL, e.g. `https://minio.example.com`. |
| `snapshot.s3.region` | `"us-east-1"` | S3 region. `us-east-1` is a safe universal default. |
| `snapshot.s3.bucket` | `""` | **Required when `s3.enabled=true`.** Bucket must already exist; the addon does not create it. |
| `snapshot.s3.prefix` | `"etcd-snapshots"` | Object-key prefix. Final key: `<prefix>/<clusterName>-<UTC-ISO8601>.db`. |
| `snapshot.s3.pathStyle` | `true` | Path-style addressing (required by MinIO, Ceph RGW, Nutanix Objects; supported by AWS S3). |
| `snapshot.s3.insecureSkipTLSVerify` | `false` | Skip TLS verification. **Lab use only.** |
| `snapshot.s3.credentialsSecret.name` | `""` | **Required when `s3.enabled=true`.** Name of an existing Kubernetes Secret in the release namespace. |
| `snapshot.s3.credentialsSecret.accessKeyKey` | `"access-key-id"` | Key inside the Secret holding the S3 access key ID. |
| `snapshot.s3.credentialsSecret.secretKeyKey` | `"secret-access-key"` | Key inside the Secret holding the S3 secret access key. |
| `snapshot.s3.uploader.image.repository` | `minio/mc` | Uploader image. |
| `snapshot.s3.uploader.image.tag` | `RELEASE.2024-11-21T17-21-54Z` | Uploader image tag. |
| `snapshot.s3.uploader.image.pullPolicy` | `IfNotPresent` | Pull policy. |
| `snapshot.s3.resources` | (see `values.yaml`) | Uploader container resource requests/limits. |

> **Fail-fast invariants.** When `snapshot.s3.enabled=true`, the chart will
> refuse to render unless `snapshot.s3.endpoint`, `snapshot.s3.bucket`, and
> `snapshot.s3.credentialsSecret.name` are all non-empty. The error message
> includes the offending key and a reference to `LLD-phase5.md §10`.

### `alerts` (Phase Observability)

The `PrometheusRule` resource is rendered only when **both** of these hold:
1. `alerts.enabled=true` (default).
2. The cluster has the Prometheus Operator's `monitoring.coreos.com/v1/PrometheusRule` CRD installed.

This makes `alerts.enabled=true` safe even on bare clusters: the install
succeeds, and a later `helm upgrade` will materialise the rule once the
operator arrives.

| Parameter | Default | Description |
|---|---|---|
| `alerts.enabled` | `true` | Master toggle. Capability-gated: a `true` setting is a no-op on clusters without the Prometheus Operator CRD. |
| `alerts.additionalLabels` | `{ release: kube-prometheus-stack }` | Labels added to the PrometheusRule so the Operator's `ruleSelector` discovers it. Override for non-default kube-prometheus-stack installs. |
| `alerts.defaultLabels` | `{}` | Labels applied to **every** alert (useful for Alertmanager routing, e.g. `team: platform`). |
| `alerts.defaultAnnotations` | `{}` | Annotations applied to every alert. |
| `alerts.runbookBaseUrl` | `https://github.com/nutanix-cloud-native/nkp-etcd-maintenance/blob/main/README.md` | Base URL for each alert's `runbook_url` annotation. Each alert appends its anchor (e.g. `#etcdmembernoleader`). Override for airgapped docs mirrors. |
| `alerts.etcdScrapeJobLabel` | `kube-etcd` | Value of the `job` label on etcd-self metrics. Override if your scrape config labels etcd differently. |
| `alerts.thresholds.dbHighUsageRatio` | `0.7` | Warning when `db_total/quota` exceeds this ratio. **Must be strictly less than `dbCriticalUsageRatio` — the chart fails to render otherwise.** |
| `alerts.thresholds.dbCriticalUsageRatio` | `0.9` | Critical when `db_total/quota` exceeds this ratio. |
| `alerts.thresholds.highFragmentationBytes` | `524288000` (500 MiB) | Warning when `db_total − db_in_use` exceeds this many bytes. |
| `alerts.thresholds.missedScheduleSeconds` | `172800` (48 h) | Warning when a CronJob has not scheduled a Job for this many seconds. |
| `alerts.for.*` | (see `values.yaml`) | Per-alert `for:` duration. Sized to avoid paging on brief, expected transients (e.g. `memberNoLeader: 1m` rides through `--move-leader` flaps). |
| `alerts.rules.<AlertName>.enabled` | `true` (each) | Per-alert opt-out. Operators with their own etcd-health alerts can disable the four etcd-health rules and keep only the CronJob-failure ones. |
| `alerts.rules.<AlertName>.severity` | `warning` or `critical` (per alert) | Override the severity label (e.g. raise `EtcdDbHighUsage` to `critical` for low-headroom fleets). |

> **Fail-fast invariant.** When `alerts.enabled=true`, the chart will refuse
> to render if `alerts.thresholds.dbHighUsageRatio >= alerts.thresholds.dbCriticalUsageRatio`.
> The error message points at `LLD-phase-observability §8.1`. This guards
> against the silent failure mode where the warning alert silences its own
> critical counterpart.

---

## Default Schedules

All schedules are evaluated in UTC by the CronJob controller. The defaults
are placed in a low-traffic window and offset so the defrag and snapshot
jobs never overlap.

| Setting | Default | Why this value |
|---|---|---|
| `defragmentation.schedule` | `30 2 * * *` | 02:30 UTC daily — a universal low-traffic window across most timezones. Offset from `02:00` to avoid the top-of-the-hour cron stampede. |
| `snapshot.schedule` | `0 3 * * *` | 03:00 UTC daily, 30 min after defrag finishes. Defrag shrinks the bbolt file → smaller, cheaper snapshot upload. Non-overlapping by design (see [Limitations and Non-Goals](#limitations-and-non-goals)). |
| `alerts.thresholds.missedScheduleSeconds` | `172800` (48 h) | Two days of grace before paging on a missed cron tick. Catches a missed daily run after one extra day, without flapping on `concurrencyPolicy: Forbid` skips. |
| `defragmentation.waitBetweenDefrags` | `1m` | Pause between consecutive per-member defrag operations so the cluster can settle. |
| `snapshot.startingDeadlineSeconds` | `300` | Skip a missed snapshot tick if the controller is more than 5 minutes late firing it (avoids stale snapshots after a long control-plane outage). |

**Customising the schedule.** Reschedule freely, but keep three rules:

1. **Keep them non-overlapping.** The two CronJobs do not coordinate (no
   lock). Use schedules whose Jobs can never run simultaneously on the
   same control-plane node.
2. **Pick UTC times.** Cron expressions are interpreted in the
   `kube-controller-manager` process timezone, which is UTC by default
   on every NKP image.
3. **Prefer odd minutes.** `30 2 * * *` rather than `0 2 * * *` spreads
   load away from the top-of-the-hour spike on shared infrastructure.

---

## Enabling and Disabling

Each feature has its own master toggle and they are fully independent.

### Default install (defrag-only, alerts on if Prometheus Operator present)

```bash
helm upgrade --install nkp-etcd-maintenance ./nkp-etcd-maintenance \
  --namespace kube-system
```

What gets created:
- `CronJob/nkp-etcd-defrag` — runs daily.
- `ServiceAccount` + `ClusterRole` + `ClusterRoleBinding`.
- `PrometheusRule/nkp-etcd-maintenance` — **only if** the cluster has
  the `monitoring.coreos.com/v1` CRD; defrag-related alerts only (the
  snapshot group is suppressed because `snapshot.enabled=false`).

### Add the snapshot CronJob (verify-only, no upload)

```bash
helm upgrade nkp-etcd-maintenance ./nkp-etcd-maintenance \
  --namespace kube-system \
  --reuse-values \
  --set snapshot.enabled=true
```

The snapshot CronJob runs daily, captures a verified snapshot, then
discards it on Pod termination. Adds the snapshot alert group to the
PrometheusRule.

### Add the snapshot CronJob + S3 upload

```bash
kubectl create secret generic etcd-backup-s3-creds \
  --namespace kube-system \
  --from-literal=access-key-id='AKIAEXAMPLEKEY' \
  --from-literal=secret-access-key='wJalrXUtnFEMI/K7MDENG/EXAMPLEKEY'

helm upgrade nkp-etcd-maintenance ./nkp-etcd-maintenance \
  --namespace kube-system \
  --reuse-values \
  --set snapshot.enabled=true \
  --set snapshot.s3.enabled=true \
  --set snapshot.s3.endpoint=https://minio.example.com \
  --set snapshot.s3.bucket=nkp-etcd-backups \
  --set snapshot.s3.credentialsSecret.name=etcd-backup-s3-creds
```

### Disable the alerts (but keep both CronJobs)

```bash
helm upgrade nkp-etcd-maintenance ./nkp-etcd-maintenance \
  --namespace kube-system \
  --reuse-values \
  --set alerts.enabled=false
```

This is the right toggle for clusters that already have their own etcd
alert rules and want to avoid duplicate paging.

### Disable a single alert (e.g. operator already has `EtcdMemberNoLeader`)

```bash
helm upgrade nkp-etcd-maintenance ./nkp-etcd-maintenance \
  --namespace kube-system \
  --reuse-values \
  --set alerts.rules.EtcdMemberNoLeader.enabled=false
```

### Disable the defrag CronJob (without uninstalling)

```bash
helm upgrade nkp-etcd-maintenance ./nkp-etcd-maintenance \
  --namespace kube-system \
  --reuse-values \
  --set defragmentation.enabled=false
```

### Disable the snapshot CronJob (without uninstalling)

```bash
helm upgrade nkp-etcd-maintenance ./nkp-etcd-maintenance \
  --namespace kube-system \
  --reuse-values \
  --set snapshot.enabled=false
```

The snapshot alert group disappears with it.

### Uninstall everything

```bash
helm uninstall nkp-etcd-maintenance --namespace kube-system
```

Removes both CronJobs, the PrometheusRule, the ServiceAccount, the
ClusterRole, and the ClusterRoleBinding. Past Job pods are not deleted —
clean them up explicitly if needed; see [`COMMANDS.md` §7](./COMMANDS.md).

---

## Snapshot CronJob (Phase 5)

### Why it exists

Defragmentation keeps the on-disk file healthy; **it does not protect you from
data loss**. If a control-plane node loses its disk, the etcd member's data
goes with it. With a recent verified snapshot you can rebuild etcd in minutes;
without one, the cluster's state is unrecoverable.

### Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  CronJob: nkp-etcd-snapshot   (schedule: "0 3 * * *", default off)  │
│  concurrencyPolicy: Forbid   backoffLimit: 0                        │
│                                                                     │
│    └─► Job ──► Pod (hostNetwork: true, control-plane nodes only)    │
│                                                                     │
│      initContainer take-snapshot                                    │
│        image: registry.k8s.io/etcd:<tag>                            │
│        command: etcdctl snapshot save  →  /snapshot/etcd.db         │
│        mounts:   etcd-pki (RO), snapshot-buffer (RW), tmp (RW)      │
│                                                                     │
│      initContainer verify-snapshot                                  │
│        image: registry.k8s.io/etcd:<tag>                            │
│        command: etcdutl snapshot status /snapshot/etcd.db           │
│        mounts:   snapshot-buffer (RO), tmp (RW)                     │
│                                                                     │
│      container     upload  (only when snapshot.s3.enabled=true)     │
│        image: minio/mc:<tag>                                        │
│        command: /bin/sh → mc alias set + mc cp                      │
│        mounts:   snapshot-buffer (RO), tmp (RW)                     │
│        env:      S3_ENDPOINT, S3_BUCKET, ... (plain)                │
│                  AWS_ACCESS_KEY_ID,                                 │
│                  AWS_SECRET_ACCESS_KEY  ← secretKeyRef              │
│                                                                     │
│      OR container noop  (when snapshot.s3.enabled=false)            │
│        image: registry.k8s.io/etcd:<tag>   (already pulled)         │
│        command: etcdctl version    (exits 0, no upload)             │
└─────────────────────────────────────────────────────────────────────┘
```

The snapshot file lives only in a Pod-scoped `emptyDir`; it never touches the
host filesystem and is garbage-collected with the Pod. See
[LLD-phase5.md](./LLD-phase5.md) §4 for the full rationale.

### Two operating modes

| Mode | Toggle | What happens |
|---|---|---|
| **Disabled** (default) | `snapshot.enabled=false` | Snapshot CronJob is not rendered at all. Defrag CronJob unaffected. |
| **Verify-only** | `snapshot.enabled=true`, `snapshot.s3.enabled=false` | Daily snapshot is taken and verified; then discarded. Useful for validating the snapshot path in CI/staging before wiring up S3. |
| **Verify + Upload** | `snapshot.enabled=true`, `snapshot.s3.enabled=true` (+ endpoint/bucket/SecretRef) | Snapshot is uploaded to S3 with key `<prefix>/<clusterName>-<UTC-ISO8601>.db`. |

### Enabling — quick start

See [`COMMANDS.md` — Phase 5: Snapshot MVP](./COMMANDS.md) for the full,
copy-pasteable command set with examples for AWS S3, MinIO, and Nutanix
Objects. The minimal sequence:

```bash
kubectl create secret generic etcd-backup-s3-creds \
  --namespace kube-system \
  --from-literal=access-key-id='AKIAEXAMPLEKEY' \
  --from-literal=secret-access-key='wJalrXUtnFEMI/K7MDENG/EXAMPLEKEY'

helm upgrade --install nkp-etcd-maintenance ./nkp-etcd-maintenance \
  --namespace kube-system \
  --set snapshot.enabled=true \
  --set snapshot.s3.enabled=true \
  --set snapshot.s3.endpoint=https://minio.example.com \
  --set snapshot.s3.bucket=nkp-etcd-backups \
  --set snapshot.s3.credentialsSecret.name=etcd-backup-s3-creds
```

### Security guarantees

1. **No plaintext credentials** in `values.yaml`, the chart, or any catalog
   override. Access keys are exclusively `secretKeyRef` references.
2. **Granular SecretKey import** (`secretKeyRef`, not `envFrom.secretRef`):
   if the operator's Secret holds additional keys in the future, they will
   NOT bleed into the upload container's environment.
3. **PKI mount scope-limited**: `/etc/kubernetes/pki/etcd` is mounted only
   into the `take-snapshot` init container. The verify and upload containers
   cannot read the etcd private key.
4. **Read-only snapshot to uploader**: the verified snapshot is mounted
   `readOnly: true` into the upload container — the uploader cannot tamper
   with what it transmits.

---

## Manual Restore Runbook

> ### ⚠️ Read this entire section before attempting a restore.
> #### Restore is intentionally a manual operator workflow. This addon will NEVER auto-restore an etcd database. Automating restore would create a foot-gun: a single corrupt, attacker-supplied, or stale snapshot could silently overwrite a healthy cluster's state. See [LLD-phase5.md §13](./LLD-phase5.md) for the full rationale.

### When to use this runbook

Use this procedure if **and only if**:

1. The etcd cluster has experienced **unrecoverable data loss** (quorum lost,
   disks destroyed, irrecoverable corruption); AND
2. You have a recent snapshot you trust (typically the most recent one
   uploaded by this addon and verified by `etcdutl snapshot status`); AND
3. You have console / SSH access to **every** control-plane node.

Do NOT use this runbook to "roll back" the cluster to an earlier state — the
right tool for that is point-in-time application backups, not etcd snapshot
restore.

### Pre-flight checklist

```
[ ] Cluster is genuinely unrecoverable (kubectl is hard-down across all CP nodes).
[ ] Snapshot file location is known (URL in S3 / object key on disk).
[ ] etcd snapshot file integrity verified locally:
        etcdutl snapshot status <file.db> -w table
[ ] Cluster topology is documented: number of CP nodes, node IPs, hostnames.
[ ] You have the original etcd PKI material (or equivalent regenerated certs).
[ ] kubeadm / NKP cluster bootstrap config is available.
[ ] Change window is approved; downtime is expected and accepted.
```

If any item is unchecked, **stop and resolve it first**.

### High-level procedure

```
1.  Stop kubelet on every CP node so the static etcd pods stop.
2.  Move the existing etcd data dir aside on every CP node (don't delete it
    yet — keep it for forensic / rollback purposes).
3.  Copy the snapshot file to every CP node.
4.  On every CP node, run `etcdutl snapshot restore` with that node's
    name, advertise-URLs, and initial-cluster string so a NEW data dir is
    materialised from the snapshot.
5.  Move the new data dir into place under /var/lib/etcd.
6.  Re-start kubelet on every CP node; the etcd static pods come back up
    against the restored data dir and form a new cluster.
7.  Validate: `etcdctl endpoint health`, `kubectl get nodes`, `kubectl get
    pods --all-namespaces`.
```

### Step-by-step procedure

> All commands below assume the snapshot file is on the node at
> `/root/etcd.db`. Substitute as appropriate. `<NODE_NAME>` and `<NODE_IP>`
> below refer to the values of the node you are running on.

#### Step 1 — Determine the original cluster's initial-cluster string

Recover it from any *surviving* control-plane node (if any), or from
configuration management. Example:

```bash
# On a surviving CP node, or from a saved etcd static-pod manifest:
grep initial-cluster /etc/kubernetes/manifests/etcd.yaml | head -1
# → --initial-cluster=cp1=https://10.22.202.156:2380,cp2=https://10.22.202.157:2380,cp3=https://10.22.202.161:2380
```

This same value MUST be passed to `etcdutl snapshot restore` on every node.

#### Step 2 — Stop kubelet on every CP node

```bash
# On EACH control-plane node:
sudo systemctl stop kubelet
sudo crictl ps | grep etcd   # confirm etcd container is gone (or stopped)
```

This brings the static etcd pods down. Kubernetes API will be hard-down.

#### Step 3 — Move the existing data dir aside (every CP node)

```bash
sudo mv /var/lib/etcd /var/lib/etcd.broken-$(date +%s)
```

We don't delete it yet — if the restore fails we want to be able to put it
back.

#### Step 4 — Restore the snapshot on every CP node

```bash
# On EACH control-plane node, with that node's specific name and IP:
sudo etcdutl snapshot restore /root/etcd.db \
  --name=<NODE_NAME> \
  --initial-cluster=cp1=https://10.22.202.156:2380,cp2=https://10.22.202.157:2380,cp3=https://10.22.202.161:2380 \
  --initial-cluster-token=etcd-cluster \
  --initial-advertise-peer-urls=https://<NODE_IP>:2380 \
  --data-dir=/var/lib/etcd
```

This rebuilds the data dir from the snapshot. Each node will hold the SAME
snapshot data, but each is registered under its own `--name` / peer URL.

#### Step 5 — Fix ownership

```bash
sudo chown -R etcd:etcd /var/lib/etcd 2>/dev/null || \
  sudo chmod -R 700 /var/lib/etcd
```

(NKP's etcd static pod runs as root, so the chown above may not apply.
`chmod 700` is the universal safe default.)

#### Step 6 — Restart kubelet on every CP node

```bash
sudo systemctl start kubelet
```

Kubelet picks up the static etcd pod manifest at
`/etc/kubernetes/manifests/etcd.yaml` and brings etcd up against the restored
data dir. Within ~30s the API server should be reachable again.

#### Step 7 — Validate

```bash
# From your workstation (kubeconfig still works because PKI is unchanged):
kubectl get nodes
kubectl get pods --all-namespaces

# Sanity-check etcd itself (exec into the etcd static pod):
kubectl -n kube-system exec -it etcd-cp1 -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint status -w table
```

You should see one entry per CP node, all `IS LEADER` correctly elected, and
matching `Raft Index` / `Raft Term` after a few seconds.

#### Step 8 — Verify cluster correctness

The cluster is now running on data from the snapshot's point-in-time. Any
state changes after that snapshot are **lost**:

- Any `kubectl apply` after the snapshot is gone — re-apply from GitOps source.
- Any in-flight workload state (PVC binding, Pod scheduling decisions) made
  after the snapshot must be reconciled.
- Reconcile Flux / ArgoCD against your git source of truth.

### Rollback (if restore failed)

If anything went wrong, the original (broken) data dir is still at
`/var/lib/etcd.broken-<timestamp>`. Stop kubelet, move it back into place,
restart kubelet, and engage Nutanix Support.

### Reference

- [etcd-io/etcd — Disaster recovery](https://etcd.io/docs/v3.5/op-guide/recovery/)
- [kubeadm — Restoring an etcd cluster from a snapshot](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/#restoring-an-etcd-cluster)
- [LLD-phase5.md §13 — Why restore is manual](./LLD-phase5.md)

---

## Observability — Events, Logs, Alerts

This addon emits three independent observability signals; the design
rationale lives in [`LLD-phase-observability.md`](./LLD-phase-observability.md).

### Signal 1 — Kubernetes Events (always on)

The native Job and CronJob controllers emit Events on every state
transition. The chart deliberately ships **no** custom event-emission
container (see LLD-phase-observability §4 / D1). Inspect with:

```bash
# Job-level Events (success / failure / pod scheduling / OOM / image pull errors)
kubectl describe job <job-name> -n kube-system

# CronJob-level Events (SuccessfulCreate, MissingJob, JobAlreadyActive)
kubectl describe cronjob nkp-etcd-defrag   -n kube-system
kubectl describe cronjob nkp-etcd-snapshot -n kube-system

# Stream Events for the whole namespace, sorted by time
kubectl get events -n kube-system --sort-by=.lastTimestamp --watch
```

See [`COMMANDS.md` §9](./COMMANDS.md#9-observability--inspecting-jobs-and-reading-failures)
for the full inspection playbook.

### Signal 2 — Clear, structured logs

| Container | Image | Log format | What you should see |
|---|---|---|---|
| `etcd-defrag` (defrag) | `ahrtr/etcd-defrag` | upstream key=value | one line per member, `Defragmenting ...`, `dbSize <before> -> <after>` |
| `take-snapshot` (init) | `registry.k8s.io/etcd` | upstream JSON | `{"level":"info","msg":"saved","path":"/snapshot/etcd.db"}` |
| `verify-snapshot` (init) | `registry.k8s.io/etcd` | tabular | one-line table from `etcdutl snapshot status` |
| `upload` (main, S3-on) | `minio/mc` | **logfmt — `[upload] phase=<name> key=value …`** | exactly 4 success lines (start / alias-set / copy / success) or one `phase=*-failed` line with `exit_code` |
| `noop` (main, S3-off) | `registry.k8s.io/etcd` | upstream | one line `etcdctl version: ...` |

**Greppable log lines.** The upload script's `[upload] phase=` prefix is the
project's only chart-emitted log format and is stable across versions.
Examples:

```bash
# Did the most recent upload succeed?
kubectl logs <pod> -n kube-system -c upload | grep '^\[upload\] phase=success'

# Why did it fail?
kubectl logs <pod> -n kube-system -c upload | grep '^\[upload\] phase=.*failed'
```

### Signal 3 — PrometheusRule alerts

When `alerts.enabled=true` and the Prometheus Operator CRD is present, the
chart ships exactly one `PrometheusRule` resource with three groups and 8
alerts. Each alert carries a `runbook_url` annotation pointing at the
matching subsection below (anchor format `#<alert-name-lowercased>`).

| Group | Alert | Severity | `for:` | Fires when |
|---|---|---|---|---|
| `etcd-health` | `EtcdMemberNoLeader` | critical | 1m | etcd member has no leader |
| `etcd-health` | `EtcdDbHighUsage` | warning | 1h | db_total / quota > 70 % |
| `etcd-health` | `EtcdDbCriticalUsage` | critical | 5m | db_total / quota > 90 % |
| `etcd-health` | `EtcdHighFragmentation` | warning | 1h | db_total − db_in_use > 500 MiB |
| `defrag` | `EtcdDefragJobFailed` | warning | 5m | a `nkp-etcd-defrag-*` Job is in Failed state |
| `defrag` | `EtcdDefragJobMissed` | warning | 30m | CronJob has not scheduled in > 48 h |
| `snapshot` | `EtcdSnapshotJobFailed` | critical | 5m | a `nkp-etcd-snapshot-*` Job is in Failed state |
| `snapshot` | `EtcdSnapshotJobMissed` | critical | 30m | CronJob has not scheduled in > 48 h |

> The `snapshot` group is rendered only when `snapshot.enabled=true`. A
> defrag-only deployment never gets paged about a snapshot CronJob that
> doesn't exist.

### Per-alert runbook

The headings below are intentionally single-word so the GitHub-rendered
anchors (e.g. `#etcdmembernoleader`) match each alert's `runbook_url`
annotation byte-for-byte.

#### EtcdMemberNoLeader

- **Severity:** critical • **for:** 1 m
- **Expression:** `etcd_server_has_leader{job="kube-etcd"} == 0`
- **What it means:** the etcd member is reporting no leader, sustained for
  longer than a normal election. The cluster has lost write quorum or is in
  a long-running election storm.
- **Triage:**
  ```bash
  # Are the static etcd pods alive on every CP node?
  kubectl get pods -n kube-system -l component=etcd -o wide

  # What does each member's log say?
  kubectl logs -n kube-system etcd-<cp-node> --tail=200

  # Brief flaps during the defrag tool's `--move-leader` step are expected;
  # sustained firing (more than a few minutes) is a real outage.
  kubectl get jobs -n kube-system | grep nkp-etcd-defrag
  ```

#### EtcdDbHighUsage

- **Severity:** warning • **for:** 1 h
- **Expression:** `etcd_mvcc_db_total_size_in_bytes / etcd_server_quota_backend_bytes > 0.7`
- **What it means:** the etcd file size on this member is more than 70 % of
  the configured `--quota-backend-bytes`, sustained for an hour. The daily
  defrag should already have reduced this; if the alert is firing, defrag
  isn't keeping up or didn't run.
- **Triage:**
  ```bash
  # Did the last defrag run succeed?
  kubectl get jobs -n kube-system -l app.kubernetes.io/name=nkp-etcd-maintenance \
    --sort-by=.metadata.creationTimestamp | tail -5

  # Inspect its logs
  kubectl logs -n kube-system <most-recent-defrag-job-pod>

  # Consider lowering the defrag-rule threshold (e.g. `dbQuotaUsage > 0.4`)
  helm upgrade nkp-etcd-maintenance ./nkp-etcd-maintenance \
    --namespace kube-system --reuse-values \
    --set defragmentation.defragRule="dbQuotaUsage > 0.4"
  ```

#### EtcdDbCriticalUsage

- **Severity:** critical • **for:** 5 m
- **Expression:** `etcd_mvcc_db_total_size_in_bytes / etcd_server_quota_backend_bytes > 0.9`
- **What it means:** db file exceeds 90 % of quota. A `NOSPACE` alarm and
  cluster-wide write halt is imminent.
- **Triage — page on-call.**
  ```bash
  # 1. Trigger a manual defrag immediately
  kubectl create job --from=cronjob/nkp-etcd-defrag \
    manual-defrag-emergency-$(date +%s) -n kube-system

  # 2. While defrag runs, investigate what is filling etcd
  kubectl get --raw=/metrics 2>/dev/null | grep apiserver_storage_objects | sort -k2 -n | tail -20

  # 3. If a NOSPACE alarm has already fired, clear it after defrag
  kubectl -n kube-system exec etcd-<cp-node> -- etcdctl alarm list
  kubectl -n kube-system exec etcd-<cp-node> -- etcdctl alarm disarm
  ```

#### EtcdHighFragmentation

- **Severity:** warning • **for:** 1 h
- **Expression:** `etcd_mvcc_db_total_size_in_bytes - etcd_mvcc_db_total_size_in_use_in_bytes > 524288000` (500 MiB)
- **What it means:** the bbolt file contains more than 500 MiB of "holes"
  (freed pages). The daily defrag should have reclaimed them. Either
  defrag didn't run (see `EtcdDefragJobMissed`), didn't help (rule did
  not fire), or the cluster is generating waste faster than the daily
  tick can compact.
- **Triage:**
  ```bash
  # Did the rule fire on the last run?
  kubectl logs -n kube-system <most-recent-defrag-job-pod> | \
    grep -i 'rule\|skipping\|defragmenting'

  # If the rule never fires, lower its fragmentation threshold:
  helm upgrade nkp-etcd-maintenance ./nkp-etcd-maintenance \
    --namespace kube-system --reuse-values \
    --set defragmentation.defragRule='dbSize - dbSizeInUse > 100*1024*1024'
  ```

#### EtcdDefragJobFailed

- **Severity:** warning • **for:** 5 m
- **Expression:** `sum by (namespace, job_name) (kube_job_status_failed{namespace="kube-system", job_name=~"nkp-etcd-defrag-.*"}) > 0`
- **What it means:** the most recent defrag Job is in the Failed state.
  Because the chart sets `backoffLimit: 0`, the Job goes Failed the moment
  any Pod exits non-zero — there are no silent retries.
- **Triage:**
  ```bash
  # 1. What does the controller say? (Events explain WHY, logs explain WHAT)
  kubectl describe job <job-name> -n kube-system

  # 2. What did the binary print? (the controller saved the Pod for you)
  kubectl logs job/<job-name> -n kube-system

  # 3. Most common root causes are documented in COMMANDS.md "Known Issues"
  ```

#### EtcdDefragJobMissed

- **Severity:** warning • **for:** 30 m
- **Expression:** `time() - kube_cronjob_status_last_schedule_time{cronjob="nkp-etcd-defrag"} > 172800` (48 h)
- **What it means:** the CronJob has not produced a Job for more than two
  days. Pure failure-counting (`EtcdDefragJobFailed`) misses this case —
  if no Job is created at all, there is nothing to mark Failed.
- **Triage:**
  ```bash
  kubectl get cronjob nkp-etcd-defrag -n kube-system
  # SUSPEND=True → someone (or an upgrade) suspended it; resume:
  kubectl patch cronjob nkp-etcd-defrag -n kube-system \
    -p '{"spec":{"suspend":false}}'

  # SUSPEND=False but LAST SCHEDULE is old → kube-controller-manager issue
  kubectl get pods -n kube-system -l component=kube-controller-manager
  ```

#### EtcdSnapshotJobFailed

- **Severity:** critical • **for:** 5 m
- **Expression:** `sum by (namespace, job_name) (kube_job_status_failed{namespace="kube-system", job_name=~"nkp-etcd-snapshot-.*"}) > 0`
- **What it means:** the most recent snapshot Job failed. The cluster's
  disaster-recovery posture is degraded until the next successful snapshot.
  This is **critical**, not warning, because defrag failures only degrade
  performance — snapshot failures degrade recoverability.
- **Triage:**
  ```bash
  # 1. Which init container failed?
  kubectl describe job <job-name> -n kube-system  # → Events show which container

  # 2. Read each container's log; phase-specific symptoms below:
  POD=$(kubectl get pods -n kube-system -l job-name=<job-name> \
    -o jsonpath='{.items[0].metadata.name}')
  kubectl logs $POD -n kube-system -c take-snapshot
  kubectl logs $POD -n kube-system -c verify-snapshot
  kubectl logs $POD -n kube-system -c upload     # only if s3.enabled=true
  ```

  Common patterns:
  - `take-snapshot` exits with `permission denied` on `server.key` → operator
    overrode `runAsUser`; reset to `0`.
  - `verify-snapshot` fails after `take-snapshot` succeeded → disk full on
    the CP node (`emptyDir` ran out).
  - `upload` logs `phase=alias-set-failed` → wrong endpoint or TLS cert
    issue.
  - `upload` logs `phase=copy-failed exit_code=1` → wrong credentials or
    bucket policy.

#### EtcdSnapshotJobMissed

- **Severity:** critical • **for:** 30 m
- **Expression:** `time() - kube_cronjob_status_last_schedule_time{cronjob="nkp-etcd-snapshot"} > 172800` (48 h)
- **What it means:** no snapshot has been taken in > 48 h. Critical because
  no new backups exist — RPO (recovery-point objective) is degrading every
  hour the alert fires.
- **Triage:** identical to `EtcdDefragJobMissed` above, plus:
  ```bash
  # Verify the snapshot CronJob still exists at all (someone may have
  # disabled it via --set snapshot.enabled=false)
  kubectl get cronjob nkp-etcd-snapshot -n kube-system
  ```

### Alert discovery and silencing

| Task | Command |
|---|---|
| Confirm the PrometheusRule is in the cluster | `kubectl get prometheusrule nkp-etcd-maintenance -n kube-system` |
| Confirm Prometheus has loaded it | Prometheus UI → Status → Rules → search "nkp-etcd-maintenance". The number of rules should be 6 (defrag-only) or 8 (with snapshot). |
| Confirm Alertmanager routes them | Alertmanager UI → silence a rule by `alertname=EtcdDefragJobFailed`. |
| Silence a single alert temporarily | `amtool silence add alertname=EtcdHighFragmentation --duration=24h --comment="known noisy"` |
| Disable a rule permanently | `helm upgrade ... --reuse-values --set alerts.rules.<AlertName>.enabled=false` |

### Adapting alerts to your environment

Three knobs cover ~90 % of real-world overrides:

- **Wrong `job` label on your etcd scrape target.** Override:
  ```
  --set alerts.etcdScrapeJobLabel=etcd-static-pod
  ```
- **Rules not discovered by Prometheus.** Your Operator's `ruleSelector`
  doesn't match `release: kube-prometheus-stack`. Inspect with:
  ```bash
  kubectl get prometheus -A -o jsonpath='{range .items[*]}{.spec.ruleSelector}{"\n"}{end}'
  ```
  then `--set alerts.additionalLabels.<key>=<value>` to match.
- **Per-alert severity tuning.** Raise `EtcdDbHighUsage` to `critical` on
  a fleet with tight quota headroom:
  ```
  --set alerts.rules.EtcdDbHighUsage.severity=critical
  ```

---

## Limitations and Non-Goals

This addon is intentionally narrow. The list below records what it
**deliberately does not do** and where the boundary sits with adjacent
tooling.

### 1. Restore is **not** automated

The chart will never auto-restore an etcd database. Restore is a destructive
operation on cluster state-of-truth, and automating it would create a
foot-gun: a single corrupt, attacker-supplied, or stale snapshot could
silently overwrite a healthy cluster. The operator workflow is the
[Manual Restore Runbook](#manual-restore-runbook) above. See
[LLD-phase5.md §13](./LLD-phase5.md) for the full rationale.

### 2. The chart does **not** manage snapshot retention or lifecycle

Snapshot retention is the **bucket's** job, not the chart's. Configure an
S3 lifecycle policy on `<bucket>/<prefix>/` (e.g. "delete objects older
than 30 days"). The chart writes one new object per snapshot run; it never
deletes any.

### 3. The chart does **not** create cloud resources

The S3 bucket, IAM user, access keys, bucket policy, KMS key, and lifecycle
policy are all operator responsibility. The chart consumes pre-existing
credentials via a `secretRef`.

### 4. The defrag and snapshot jobs do **not** coordinate

There is no chart-level lock between them. The default schedules (02:30
and 03:00 UTC) place them ~30 min apart on purpose. If you reschedule,
keep them non-overlapping — running both at once on the same CP node is
unnecessary I/O contention.

### 5. Single-cluster scope per Helm release

Each `helm install` manages exactly one cluster's etcd. Fleet-wide
deployment uses the Kommander catalog application
([Phase 3](#phase-3--kommander-catalog-application)), not multi-cluster
Helm releases.

### 6. The chart does **not** emit Kubernetes Events from its own containers

We deliberately rely on the native `Job` / `CronJob` controllers' Events.
A custom event-emitter would duplicate signal and require an additional
RBAC grant. See [LLD-phase-observability §4 D1](./LLD-phase-observability.md).

### 7. The chart does **not** poll metrics to gate defrag

`etcd-defrag`'s built-in `--defrag-rule` already evaluates `dbSize`,
`dbSizeInUse`, and `dbQuotaUsage` against live etcd metadata at runtime.
A second metrics-based gate would be redundant.

### 8. Unsupported cluster topologies

- **External etcd** — etcd running outside the K8s cluster (e.g. on a
  separate VM). The chart assumes `127.0.0.1:2379` via `hostNetwork`.
- **Hosted control planes** — AKS, EKS, GKE, ROSA, OKD-Hosted. The
  control-plane nodes are not visible to the workload cluster, so neither
  CronJob can land on them.
- **`etcd-druid` / operator-managed etcd** — these stacks run etcd as a
  StatefulSet, not static pods; the PKI paths and connection model differ.
- **Clusters whose admission policy denies `hostPath`** — the chart must
  mount `/etc/kubernetes/pki/etcd`.

The Phase 3 preflight Job at
[`kommander/preflight/topology-check-job.yaml`](./kommander/preflight/topology-check-job.yaml)
detects all four and writes the verdict into
`kube-system/ConfigMap/nkp-etcd-maintenance-topology` for fleet-wide audit.

### 9. The PrometheusRule does **not** ship the full etcd mixin

We ship 8 maintenance-relevant alerts only. Operators running a full
observability stack should layer the upstream etcd mixin (or
kube-prometheus-stack's etcd ServiceMonitor + recording rules) for richer
SLO / quorum-loss / latency alerts. Our `EtcdMemberNoLeader` is the
single etcd-quorum alert we ship because it is also the symptom most
likely to be **caused** by a misbehaving defrag run.

### 10. Alerts assume kube-prometheus-stack labelling defaults

`additionalLabels.release: kube-prometheus-stack` is the kube-prometheus-stack
default. Other operator installs (rancher-monitoring, OpenShift's
cluster-monitoring-operator) use different `ruleSelector` labels —
override via `alerts.additionalLabels`. See
[Adapting alerts to your environment](#adapting-alerts-to-your-environment).

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  kube-system namespace                                       │
│                                                             │
│  CronJob: nkp-etcd-defrag  (schedule: "30 2 * * *")        │
│  concurrencyPolicy: Forbid                                  │
│                                                             │
│    └─► Job ──► Pod (hostNetwork: true)                      │
│                  nodeSelector: control-plane                 │
│                  toleration:   control-plane:NoSchedule     │
│                                                             │
│                  Container: etcd-defrag                     │
│                  ┌──────────────────────────────────┐       │
│                  │ --endpoints=https://127.0.0.1:2379│       │
│                  │ --cluster                         │       │
│                  │ --leader-last=true                │       │
│                  │ --defrag-rule="..."               │       │
│                  │ --cacert / --cert / --key         │       │
│                  └──────────────────────────────────┘       │
│                        │ readOnly volumeMount               │
│                        ▼                                    │
│              hostPath: /etc/kubernetes/pki/etcd             │
└─────────────────────────────────────────────────────────────┘

RBAC
  ServiceAccount:      nkp-etcd-maintenance-sa
  ClusterRole:         nkp-etcd-maintenance-role  (events: create/patch/update)
  ClusterRoleBinding:  nkp-etcd-maintenance-rolebinding
```

### Why `hostNetwork: true`?

etcd on kubeadm clusters listens on `127.0.0.1:2379` (loopback only). A
container's default network namespace cannot reach the host loopback, so
`hostNetwork: true` is required to share the host's network namespace and make
the endpoint reachable.

### Why control-plane `nodeSelector` + `toleration`?

etcd only runs on control-plane nodes, so there is no value in scheduling the
job elsewhere. The `NoSchedule` taint on control-plane nodes prevents regular
workloads from landing there; the toleration in this chart explicitly opts in.
The legacy `node-role.kubernetes.io/master` toleration is included for
compatibility with older kubeadm versions.

---

## How etcd-defrag Works: The Algorithm

Understanding what the tool actually does inside etcd helps explain why
defragmentation is safe, necessary, and non-destructive.

### Step 1 — Compaction (automatic pre-step)

The Kubernetes API server tells etcd to **compact** its history every 5 minutes
by default. Compaction deletes old key revisions that are no longer needed.

However, compaction is like deleting rows from a database — the rows disappear
logically, but the **pages** (fixed-size disk blocks, typically 4 KB) that held
them are now empty. bbolt (etcd's storage engine) marks these pages as "free"
in an internal free-list but does **not** shrink the file or move data around.
The result: a file full of holes.

```
Before compaction:          After compaction:
┌──────────────────┐        ┌──────────────────┐
│ live data        │        │ live data        │
│ live data        │        │ live data        │
│ live data        │        │ live data        │
│ live data        │        │ [empty page]     │ ← freed but still
│ old revision     │ ──────►│ [empty page]     │   occupying disk
│ old revision     │        │ [empty page]     │
│ old revision     │        │ [empty page]     │
└──────────────────┘        └──────────────────┘
 file size: large            file size: SAME (unchanged)
```

### Step 2 — Rule evaluation

Before touching anything, `etcd-defrag` evaluates the configured
`--defrag-rule` expression against live metrics. If the expression is `false`,
the entire defrag step is skipped. This prevents unnecessary I/O on a healthy
cluster.

The two variables in the default rule:

| Variable | Meaning |
|---|---|
| `dbQuotaUsage` | `dbSize ÷ quota` — how much of the total allowed quota is used |
| `dbSize` | Physical file size on disk (bytes) |
| `dbSizeInUse` | Bytes actually occupied by live data |
| `dbSize - dbSizeInUse` | Wasted space (holes/free pages) |

### Step 3 — Defragmentation (bbolt Compact algorithm)

When the rule fires, `etcd-defrag` calls etcd's `Defragment` RPC on each
member. Internally, etcd runs bbolt's `Compact()` operation:

```
Source DB (fragmented)        Destination DB (new file)
┌──────────────────┐          ┌──────────────────┐
│ live page A      │ ────────►│ live page A      │
│ [empty page]     │   skip   │ live page B      │
│ [empty page]     │   skip   │ live page C      │
│ live page B      │ ────────►│ live page D      │
│ [empty page]     │   skip   └──────────────────┘
│ live page C      │ ────────► new file is smaller;
│ live page D      │ ────────► all pages contain real data
└──────────────────┘
```

1. A **new, empty** bbolt file is created alongside the existing one.
2. All live b-tree pages are **walked and copied sequentially** into the new
   file, skipping every free page.
3. The new file is **atomically swapped** to replace the old one.
4. The old fragmented file is deleted.

The result is a file where every page contains real data — no gaps, no holes.

### Step 4 — Leader-safe ordering (`--move-leader`)

`etcd-defrag` processes members in order: **non-leaders first, then the
leader**. When it is the leader's turn, it first issues a `MoveLeader` RPC to
transfer the leadership role to a healthy follower. Only after leadership has
moved does it defragment the former leader.

This ensures the cluster always has an active, non-defragging leader and
maintains write availability throughout the entire maintenance window.

### What the numbers mean in practice

From the first successful run on `nkp-harsh-test-dev-41` (2026-05-29):

```
dbSize:      78,340,096 bytes  (~74.7 MB)  ← physical file on disk
dbSizeInUse: 37,093,376 bytes  (~35.4 MB)  ← live data after compaction
Fragmentation: ~39.3 MB                    ← wasted space (holes)
```

The defrag rule threshold (`dbSize - dbSizeInUse > 200 MB`) was **not met**
(39 MB < 200 MB), so defragmentation was **correctly skipped**. The database
is healthy. The tool ran compaction, evaluated the rule, and exited cleanly —
this is the expected steady-state behaviour on a low-churn cluster.

---

## Security Strategy: Defense in Depth

The defrag pod must be able to read the etcd `server.key` to authenticate
and do its job — so instead of hiding the key, we **armor the pod itself**
to make intrusion or misuse nearly impossible. The strategy layers four
independent controls, each of which remains effective even if the others
are bypassed.

---

### Layer 1 — Ephemeral (The Moving Target)

The pod is spawned by a CronJob, does its work, and terminates. The entire
lifetime of the process is **5–10 seconds per day**.

> **Benefit:** Eliminates the attack window. A threat actor trying to scan
> or pivot through this pod would need to time an exploit to a window that
> is open for less than 0.001% of the day.

---

### Layer 2 — Zero Attack Surface (No Open Doors)

The pod hosts no web server, no open listening port, and no API endpoint.
It only makes **outbound TLS connections** to `127.0.0.1:2379`.

> **Benefit:** There is no inbound network entry point through which a
> remote attacker could send malicious commands. You cannot hack a door
> that does not exist.

---

### Layer 3 — Immutable Filesystem (The Read-Only Trap)

The container runs with `readOnlyRootFilesystem: true`. Its own filesystem
is entirely read-only, and the etcd PKI volume is also mounted `readOnly: true`.

> **Benefit:** Even if an attacker gained code execution inside the container,
> they cannot download, write, or execute any new files — no malware drops,
> no persistence, no lateral tooling.

---

### Layer 4 — Node Isolation (The VIP Section)

The pod is scheduled **exclusively on tainted control-plane nodes** via
`nodeSelector` and `tolerations`. Worker nodes, where user applications run,
cannot host this pod.

> **Benefit:** Physically separates the etcd credentials from the blast
> radius of a compromised user workload. A hacked web app on a worker node
> cannot "jump" to access the etcd key — it is on a completely different,
> tainted node that the hacked app has no permission to reach.

---

### Summary

| Layer | Control | What it stops |
|---|---|---|
| 1 — Ephemeral | CronJob lifetime < 10 seconds | Eliminates the attack window |
| 2 — No open ports | Outbound-only TLS | Blocks all remote inbound attacks |
| 3 — Read-only filesystem | `readOnlyRootFilesystem: true` | Prevents malware installation |
| 4 — Node isolation | Control-plane taint + `nodeSelector` | Blocks lateral movement from worker nodes |

> We give the tool the key, but we make the tool **invisible, doorless,
> locked, and isolated**. The risk of credential theft is exceptionally low.

---

## Operational Notes

**Choosing a schedule**

Pick a low-traffic window. Defragmentation briefly holds an exclusive lock on
the bbolt file, which can add a few milliseconds of latency to etcd writes.
The default `02:30` daily is suitable for most clusters; weekly (`0 3 * * 0`)
is a reasonable alternative for low-churn clusters.

**Defrag rule tuning**

The default rule fires when either:
- `dbQuotaUsage > 0.5` — db file is more than 50 % of the configured quota, or
- `dbSize - dbSizeInUse > 200 MiB` — more than 200 MiB of free space is trapped
  inside the file.

Tighten or relax these thresholds to match your cluster's churn rate.

**Air-gapped clusters**

Set `image.repository` to your internal registry mirror and add any required
pull secrets via `imagePullSecrets`.

**Verifying a run manually**

```bash
# Trigger the job immediately (without waiting for the next cron tick)
kubectl create job --from=cronjob/nkp-etcd-defrag manual-defrag-$(date +%s) \
  -n kube-system

# Follow the logs
kubectl logs -n kube-system -l job-name=manual-defrag-... -f
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Pod stuck in `Pending` | No control-plane nodes schedulable | Verify `nodeSelector` label exists: `kubectl get nodes --show-labels` |
| `connection refused` on etcd endpoint | `hostNetwork` not effective | Confirm the pod spec has `hostNetwork: true` |
| `certificate signed by unknown authority` | Wrong PKI path | Check `defragmentation.etcdPkiHostPath` matches the actual host path |
| Job skipped (no defrag performed) | `--defrag-rule` evaluated to `false` | Check actual db metrics; lower the thresholds if needed |
| Overlapping runs | Previous job still running at cron tick | `concurrencyPolicy: Forbid` prevents this by design; the tick is skipped |

---

## Phase 3 — Kommander Catalog Application

Phase 3 packages this validated chart as a **Kommander-managed catalog
application** so it can be enabled fleet-wide through the standard NKP /
Kommander platform-app pipeline rather than `helm install`. Full design and
work-plan in [`LLD-phase3.md`](./LLD-phase3.md). The scaffold below is
already in the repo:

| Deliverable | Location | What it is |
|---|---|---|
| Catalog Application CR | `kommander/catalog/0.1.0/application.yaml` | Points Kommander at the published chart (OCI) and the defaults ConfigMap. |
| Catalog defaults | `kommander/catalog/0.1.0/defaults/cm.yaml` | Default `values.yaml` shipped with the catalog (overridable). |
| Catalog metadata | `kommander/catalog/0.1.0/metadata.yaml` | UI display name, description, pre-install advisory. |
| AppDeployment example | `kommander/examples/appdeployment.yaml` | Working example: opt one cluster in with custom 03:00 schedule. |
| KommanderCluster example | `kommander/examples/kommandercluster-override.yaml` | Working example: enable the addon at cluster-attach time. |
| Preflight topology validator | `kommander/preflight/topology-check-job.yaml` | Runs on a candidate workload cluster; writes PASS/FAIL into a ConfigMap. Catches external etcd, managed control planes, non-kubeadm distros. |

### Quick mental model

```
Catalog repo (this dir's kommander/)
    │ ─── Application CR + defaults ConfigMap + chart pointer
    ▼
Kommander management cluster
    │ ─── AppDeployment + user override ConfigMap (per cluster)
    ▼
Flux HelmRelease federated to workload cluster
    │ ─── values: chart defaults ← catalog defaults ← user overrides
    ▼
CronJob nkp-etcd-defrag in kube-system on the workload cluster
```

### How upgrade independence works (one-paragraph version)

The chart only consumes K8s GA APIs (`batch/v1`, `rbac/v1`, `core/v1`) and
pins the defrag binary by exact tag. Bumping the K8s minor never forces a
chart bump; bumping `etcd-defrag` only requires a chart re-release and a
field edit in `application.yaml`. Phase 3 §9 of the LLD covers this in detail.

### Unsupported topologies — one-paragraph version

External etcd, hosted control planes (AKS/EKS/GKE), `etcd-druid`-style
operator-managed etcd, and clusters whose admission policy denies `hostPath`
are not supported. The preflight Job at
`kommander/preflight/topology-check-job.yaml` detects all four and writes
the verdict into `kube-system/ConfigMap/nkp-etcd-maintenance-topology` so a
platform team can audit fleet-wide compatibility with one `kubectl get cm`.
Phase 3 §10 of the LLD has the full table.

---

## License

This chart is maintained by the NKP Platform Engineering team and wraps the
[ahrtr/etcd-defrag](https://github.com/ahrtr/etcd-defrag) open-source tool,
which is licensed under the Apache 2.0 License.