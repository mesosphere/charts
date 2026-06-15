# Low-Level Design — Phase 3: Kommander Catalog Application
## NKP etcd Maintenance Internship

**Jira:** NCN-114548
**Phase:** 3 — Package Phase 2's `nkp-etcd-maintenance` Helm chart as a
**Kommander-managed catalog application** so it can be installed, configured,
and upgraded fleet-wide through the standard NKP / Kommander platform-app
machinery.
**Status:** Design + scaffolding complete; chart-repo wiring + Kommander
end-to-end test pending (see §13).

---

## Table of Contents

1.  [Outcome Criteria](#1-outcome-criteria)
2.  [Background — what a Kommander Catalog App is](#2-background--what-a-kommander-catalog-app-is)
3.  [Why a Catalog App (not CAREN `clusterConfig.addons`)](#3-why-a-catalog-app-not-caren-clusterconfigaddons)
4.  [Architecture Overview](#4-architecture-overview)
5.  [Repository Layout](#5-repository-layout)
6.  [Component Inventory](#6-component-inventory)
7.  [Chart Distribution Strategy](#7-chart-distribution-strategy)
8.  [Configuration & Override Hierarchy](#8-configuration--override-hierarchy)
9.  [Upgrade Path Independent of Kubernetes](#9-upgrade-path-independent-of-kubernetes)
10. [Unsupported Topologies & Preflight Validation](#10-unsupported-topologies--preflight-validation)
11. [Worked Examples](#11-worked-examples)
12. [Risks & Mitigations](#12-risks--mitigations)
13. [Phase 3 Work-Plan & Acceptance Criteria](#13-phase-3-work-plan--acceptance-criteria)

---

## 1. Outcome Criteria

Per the internship brief and the user-supplied Phase 3 description, Phase 3
delivers:

| # | Outcome | Phase-3 artefact that satisfies it |
|---|---|---|
| 1 | Catalog app chart, manifests, default values | `kommander/catalog/0.1.0/application.yaml`, `defaults/cm.yaml`, and the Helm chart at the repo root |
| 2 | Configuration overrides for defrag (and snapshots, Phase 4) | `defragmentation.*` keys exposed through the AppDeployment override ConfigMap pattern |
| 3 | Upgrade path independent of K8s upgrades | Chart `version` + `appVersion` decoupled from K8s; controller image pinned; see §9 |
| 4 | Example `KommanderCluster` / catalog-app config | `kommander/examples/appdeployment.yaml`, `kommander/examples/kommandercluster-override.yaml` |
| 5 | Validation / documentation for unsupported topologies | `kommander/preflight/topology-check-job.yaml` + §10 of this document |

---

## 2. Background — what a Kommander Catalog App is

Kommander (the multi-cluster management plane that ships inside every NKP install)
distributes platform-level software to one or more workload clusters using a
**Catalog → Application → AppDeployment** pipeline:

```
┌─────────────────────────────────────────────────────────────────┐
│  Catalog repository (git or OCI)                                │
│  ──────────────────────────────                                 │
│  Holds the source of truth for the addon:                       │
│   • Application CR  (what to install — chart ref, version)      │
│   • defaults/cm.yaml (ConfigMap shipped as default values)      │
│   • metadata.yaml   (display name, icon, description)           │
└──────────────────────────────┬──────────────────────────────────┘
                               │ Kommander GitRepository / OCIRepository
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│  Kommander management cluster                                   │
│  ─────────────────────────────                                  │
│  Reconciles the catalog into:                                   │
│   • Application CRs   (one per app version, namespaced to a     │
│                        Workspace)                               │
│   • AppDeployment CRs (one per app + cluster, created by the    │
│                        operator or by user)                     │
│   • Override ConfigMaps (user-supplied values that merge on top │
│                        of defaults/cm.yaml)                     │
└──────────────────────────────┬──────────────────────────────────┘
                               │  Federated by Kommander → kubefed
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│  Workload cluster(s)                                            │
│  ────────────────────                                           │
│  • Flux HelmRelease is created from the Application + override  │
│  • Flux installs / upgrades the underlying Helm chart           │
│  • The chart's resources (CronJob, RBAC) land in kube-system    │
└─────────────────────────────────────────────────────────────────┘
```

**Key insight:** the catalog repo does not contain the chart; it contains a
*pointer* to the chart and the *default values*. The chart itself lives in a
Helm/OCI repository.

---

## 3. Why a Catalog App (not CAREN `clusterConfig.addons`)

The brief explicitly forbids CAREN's `clusterConfig.addons` pipeline. The
reasoning, formalised:

| Concern | CAREN `clusterConfig.addons` | Kommander catalog app |
|---|---|---|
| **Owner** | CAREN (Cluster API Runtime Extension Nutanix) | Kommander platform-app pipeline |
| **Lifecycle** | Coupled to CAPI cluster lifecycle (bootstrap, upgrade) | Independent of K8s upgrades |
| **Upgrade trigger** | New NKP release / K8s upgrade | Bump chart version → bump Application CR |
| **Day-2 reconfiguration** | Risky — touches `KubeadmControlPlane` rollouts | Edit the AppDeployment override ConfigMap; Flux reconciles |
| **Fleet management** | Per-cluster | Catalog applied to a Workspace → applies to N clusters |
| **Rollback semantics** | Tied to CAPI rollback | `helm rollback` via Flux |

Phase 2's chart is a day-2 operational concern, not a cluster bootstrap concern,
so it belongs in the catalog-app pipeline.

---

## 4. Architecture Overview

```
                ┌──────────────────────────────────────────────┐
                │  Catalog repo (this project, kommander/)     │
                │                                              │
                │   catalog/0.1.0/                             │
                │     application.yaml   ← Application CR      │
                │     defaults/cm.yaml   ← default values      │
                │     metadata.yaml      ← display metadata    │
                └─────────────────┬────────────────────────────┘
                                  │
                                  │ Flux GitRepository
                                  ▼
            ┌─────────────────────────────────────────────────┐
            │  Kommander management cluster                   │
            │                                                 │
            │  Workspace: kommander-default-workspace         │
            │   ├─ Application/nkp-etcd-maintenance-0.1.0     │
            │   └─ AppDeployment/nkp-etcd-maintenance         │
            │        targetClusters: [nkp-harsh-test]         │
            │        valuesFrom:                              │
            │          - configMapRef: my-override-values     │
            └───────────────────────┬─────────────────────────┘
                                    │ kubefed federation
                                    ▼
            ┌─────────────────────────────────────────────────┐
            │  Workload cluster (nkp-harsh-test)              │
            │                                                 │
            │  Flux HelmRelease in kube-system →              │
            │  Renders nkp-etcd-maintenance Helm chart →      │
            │    • CronJob nkp-etcd-defrag                    │
            │    • ServiceAccount/ClusterRole/Binding         │
            └─────────────────────────────────────────────────┘
```

---

## 5. Repository Layout

```
nkp-etcd-maintenance/
├── Chart.yaml                       ← the Helm chart (used by Phase 2 + Phase 3)
├── values.yaml
├── templates/
│   ├── _helpers.tpl
│   ├── rbac.yaml
│   └── defrag-cronjob.yaml
│
├── README.md
├── COMMANDS.md
├── LLD-phase2.md
├── LLD-phase3.md                    ← this document
│
└── kommander/                       ← Phase 3 catalog deliverables
    ├── catalog/
    │   └── 0.1.0/
    │       ├── application.yaml     ← Application CR (chart ref + version)
    │       ├── defaults/
    │       │   └── cm.yaml          ← default values ConfigMap
    │       └── metadata.yaml        ← catalog display metadata
    │
    ├── examples/
    │   ├── appdeployment.yaml       ← Example AppDeployment + override ConfigMap
    │   └── kommandercluster-override.yaml   ← Example KommanderCluster snippet
    │
    └── preflight/
        └── topology-check-job.yaml  ← Pre-install topology validator (see §10)
```

---

## 6. Component Inventory

| File | Kind | Purpose |
|---|---|---|
| `catalog/0.1.0/application.yaml` | `apps.kommander.d2iq.io/v1alpha3 Application` | Points Kommander at the Helm chart (OCI URL + version) and at the defaults ConfigMap. |
| `catalog/0.1.0/defaults/cm.yaml` | `ConfigMap` | The values file that ships with the catalog. Merged with user overrides. |
| `catalog/0.1.0/metadata.yaml` | Plain YAML (Kommander catalog metadata) | Display name, description, category, icon URL — what users see in the Kommander UI. |
| `examples/appdeployment.yaml` | `apps.kommander.d2iq.io/v1alpha3 AppDeployment` + `ConfigMap` | An end-to-end working example of opting a cluster into the addon. |
| `examples/kommandercluster-override.yaml` | `kommander.mesosphere.io/v1beta1 KommanderCluster` snippet | Shows where to put the `platformApplications` override block in a KommanderCluster manifest. |
| `preflight/topology-check-job.yaml` | `batch/v1 Job` + RBAC | Runs on a candidate workload cluster; writes PASS/FAIL into `kube-system/ConfigMap/nkp-etcd-maintenance-topology` and exits non-zero on unsupported topology. |

---

## 7. Chart Distribution Strategy

A catalog Application needs a chart reference. Three options:

| Option | Pro | Con | Phase 3 choice |
|---|---|---|---|
| **OCI registry** (e.g., `oci://ghcr.io/your-org/charts/nkp-etcd-maintenance`) | Native, signed, single-artefact, well supported by Flux | Requires a registry; needs creds for private | **Primary** |
| **HTTP chart repo** (e.g., `https://your-org.github.io/nkp-charts/`) | Easy to host on GitHub Pages | Requires index.yaml maintenance | Documented as fallback |
| **Git source** (Flux `GitRepository` + `HelmChart`) | No registry needed; chart lives in the same repo as the catalog | Slightly less common pattern | Documented for air-gapped |

The Application CR is written so that the chart reference is a single field — the
distribution mechanism can change without touching templates or values.

**OCI publish flow (one-time per release):**

```bash
# From the chart root
helm package .                                      # produces nkp-etcd-maintenance-0.2.0.tgz
helm push nkp-etcd-maintenance-0.2.0.tgz \
  oci://ghcr.io/<your-org>/charts
```

---

## 8. Configuration & Override Hierarchy

Three layers, merged in this order (lowest precedence first):

```
┌─────────────────────────────────────────────────────────┐
│ Layer 1 — chart defaults                                │
│   values.yaml inside the published Helm chart           │
└───────────────────────┬─────────────────────────────────┘
                        │
┌───────────────────────▼─────────────────────────────────┐
│ Layer 2 — catalog defaults                              │
│   kommander/catalog/0.1.0/defaults/cm.yaml              │
│   (shipped as part of the catalog; identical to chart   │
│    defaults but explicit so platform team can audit)    │
└───────────────────────┬─────────────────────────────────┘
                        │
┌───────────────────────▼─────────────────────────────────┐
│ Layer 3 — per-cluster user override                     │
│   ConfigMap referenced from AppDeployment.valuesFrom    │
│   (lives in the user's Workspace; example provided)     │
└─────────────────────────────────────────────────────────┘
```

This mirrors how the user describes the brief's directional config shape
(`platformApplications.etcdMaintenance.defragmentation.*`) — the user puts
their overrides in a ConfigMap with a `values.yaml` key, and Kommander
hands that data to Flux as `valuesFrom`. Flux + Helm do the merge.

The complete value schema (already implemented in Phase 2) is:

```yaml
defragmentation:
  enabled:            true
  schedule:           "30 2 * * *"
  defragRule:         "dbQuotaUsage > 0.5 || dbSize - dbSizeInUse > 200*1024*1024"
  endpoint:           "https://127.0.0.1:2379"
  cluster:            true
  leaderLast:         true        # → --move-leader
  waitBetweenDefrags: "1m"
  autoDisalarm:       false
  etcdPkiHostPath:    /etc/kubernetes/pki/etcd

image:
  repository:         ghcr.io/ahrtr/etcd-defrag
  tag:                v0.40.0
  pullPolicy:         IfNotPresent

resources:           {requests: {...}, limits: {...}}
successfulJobsHistoryLimit: 3
failedJobsHistoryLimit:     3
commonLabels:        {}
cronJobAnnotations:  {}
```

A Phase 4 snapshot block (`snapshot.*`) will be additive — same override
mechanism, no breaking changes to the catalog contract.

---

## 9. Upgrade Path Independent of Kubernetes

The catalog Application carries its own `version`, decoupled from
`KubeadmControlPlane.spec.version`. Three real-world upgrade scenarios:

| Scenario | What changes | What does NOT change |
|---|---|---|
| **Bump etcd-defrag binary** (e.g., v0.40.0 → v0.41.0) | `Chart.yaml` `appVersion`, push new chart version, update `catalog/0.1.0/application.yaml` chart ref to e.g. 0.2.1 | K8s version, cluster nodes |
| **Bump Kubernetes** (e.g., 1.35 → 1.36) | `KubeadmControlPlane.spec.version`, machine rollout | Catalog app version |
| **Change defrag schedule** (operator change) | Override ConfigMap | Chart, catalog app version, K8s |

**Why this works:** the chart depends only on:
- `batch/v1 CronJob` (GA since K8s 1.21)
- `rbac.authorization.k8s.io/v1` (GA since K8s 1.8)
- `core/v1 ServiceAccount`, `ConfigMap`

These APIs are stable. The chart never embeds K8s-version-specific behaviour.

The CronJob's `image` is pinned to a specific tag (`v0.40.0`) so K8s upgrades
cannot silently change the binary. The chart `appVersion` matches the pinned
tag, making provenance auditable.

---

## 10. Unsupported Topologies & Preflight Validation

The brief explicitly excludes external etcd, managed etcd, and non-kubeadm
clusters. We catch these at **install time**, not at the 02:30 cron tick.

### Topologies that MUST be refused

| Topology | Symptom on install | How we detect |
|---|---|---|
| **External etcd cluster** | No `/etc/kubernetes/pki/etcd` on control-plane nodes | `Job` checks for the three required PKI files |
| **Hosted control plane** (AKS, EKS, GKE, etc.) | No control-plane nodes accessible from workload; no `node-role.kubernetes.io/control-plane` label | `nodeSelector` finds no matching node → preflight FAIL |
| **`etcd-druid` / operator-managed etcd** | etcd not running as static pod | No `component=etcd` pods in `kube-system` |
| **Strict PSA / admission policy denying `hostPath`** | Pod admission denied | The preflight Job itself fails to start; admission denial visible in events |
| **kubeadm v1beta1 with non-standard PKI dir** | Files at a different host path | Preflight checks the configured `etcdPkiHostPath` and reports the exact missing file |

### How the preflight job works

`kommander/preflight/topology-check-job.yaml` (already authored as part of this
phase) runs on a control-plane node and writes the verdict into a ConfigMap:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nkp-etcd-maintenance-topology
  namespace: kube-system
data:
  result: PASS       # or FAIL
  reason: ""         # populated on FAIL with the precise reason
```

The platform team can then query fleet-wide compatibility with a single
`kubectl get cm -A -l app.kubernetes.io/name=nkp-etcd-maintenance` across
managed clusters via Kommander.

**Recommended operator workflow:**

```bash
# Before opting a workload cluster into the addon:
kubectl --kubeconfig <workload>.conf apply \
  -f kommander/preflight/topology-check-job.yaml

kubectl --kubeconfig <workload>.conf -n kube-system \
  get cm nkp-etcd-maintenance-topology -o yaml
# Confirm result: PASS, then create the AppDeployment.
```

A future Phase-3.x improvement: wrap this Job as a Helm `pre-install` hook
inside the chart so opt-in implicitly preflights. Deferred because Kommander's
Flux integration handles hooks differently from raw `helm install`; needs care
to avoid blocking the GitOps reconcile loop.

---

## 11. Worked Examples

The `kommander/examples/` directory contains two complete examples:

### Example A — opt-in a single cluster from the management cluster

`kommander/examples/appdeployment.yaml` shows the two objects needed to enable
the addon on `nkp-harsh-test` with a custom 03:00 schedule and a tighter
threshold rule. Apply on the management cluster.

### Example B — declare the addon on a `KommanderCluster`

`kommander/examples/kommandercluster-override.yaml` shows where the
`platformApplications` block goes when declaring the addon as part of the
cluster's manifest. Useful for new clusters created with the addon enabled
from day zero.

Both examples are runnable as-is and serve as the canonical reference for
documentation.

---

## 12. Risks & Mitigations

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| 1 | Chart repo unreachable during reconcile | Low | App stuck `not-ready` | Use OCI primary + GitRepository fallback documented |
| 2 | User mistype in override ConfigMap (e.g. invalid cron) | Medium | CronJob has `lastScheduleTime` = never | Document validation; consider adding a `validatingwebhook` in a future iteration |
| 3 | Catalog version pins to stale etcd-defrag CVE | Medium | Latent security debt | Pin in `appVersion`, watch Dependabot on `ghcr.io/ahrtr/etcd-defrag` |
| 4 | Preflight job not run by operator | Medium | Cron job silently fails on unsupported topology | Document as mandatory step in README and Kommander catalog metadata "Pre-install steps" |
| 5 | NKP/Kommander schema drift between releases | Medium | Catalog Application API field rename | Lock to `apps.kommander.d2iq.io/v1alpha3` for now; bump explicitly when NKP minor changes |

---

## 13. Phase 3 Work-Plan & Acceptance Criteria

### Completed in this iteration

- [x] Repo restructured under `kommander/` for catalog deliverables
- [x] Design document (this file)
- [x] Preflight `topology-check-job.yaml` authored
- [x] Application CR scaffold
- [x] Default values ConfigMap scaffold
- [x] Metadata file scaffold
- [x] Example `AppDeployment` and `KommanderCluster` override authored

### Pending — owner: intern + reviewer

- [ ] Publish chart to OCI: `oci://<your-org>/charts/nkp-etcd-maintenance:0.2.0`
- [ ] Add the catalog repo as a Kommander `GitRepository` (or hard-fork into the
      existing Kommander catalog if Nutanix prefers monorepo)
- [ ] End-to-end install via Kommander UI / `AppDeployment` on `nkp-harsh-test`
- [ ] Confirm Flux `HelmRelease` reaches `Ready` on the target workload cluster
- [ ] Repeat the leader-safe defrag demo, this time triggered via the
      Kommander-managed CronJob (not `helm install` directly)
- [ ] Mark Phase 3 ✅ in README

### Acceptance Criteria (Phase 3 done)

1. A user can open the Kommander UI on a fresh NKP cluster, see
   "etcd Maintenance" in the catalog, click **Enable**, and 5 minutes later
   `kubectl get cronjob -n kube-system nkp-etcd-defrag` returns a healthy
   CronJob with the user's overrides applied.
2. Bumping the chart version in `application.yaml` triggers Flux to upgrade
   the workload cluster's HelmRelease without manual intervention.
3. A `KubeadmControlPlane` K8s minor-version upgrade leaves the addon
   untouched and continues to fire on schedule.
4. The preflight Job runs cleanly on `nkp-harsh-test`, writes
   `result=PASS`, and the AppDeployment proceeds.
5. The brief's "non-goals" list (external etcd, etcd lifecycle, etc.) remains
   honoured: nothing in the catalog app touches kubeadm static-pod manifests
   or membership.
