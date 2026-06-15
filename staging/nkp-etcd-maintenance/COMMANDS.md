# Command Reference — nkp-etcd-maintenance

This document records every command used to develop, validate, and deploy the
`nkp-etcd-maintenance` Helm chart, grouped by phase. Each entry explains
**what the command does**, **why it was needed**, and **what to expect** from
the output.

---

## Current State (as of 2026-06-01)

```
Cluster:   nkp-harsh-test  (3 control-plane + 2 worker, NKP v2.18.0-dev.41, K8s v1.35.2)
Endpoint:  10.22.203.172:6443  (internal CP-LB)  /  10.22.203.173 (Kommander UI ingress)
Kubeconfig: /Users/harsh.jha/workspace/nkp-cluster(CPreplica3)/nkp-harsh-test.conf
Helm release: nkp-etcd-maintenance  REVISION 3 (deployed 2026-06-01 16:12 IST)
```

| Item | State |
|---|---|
| Old single-CP cluster | ✅ Deleted (`/Users/harsh.jha/nkp-cluster/nkp delete cluster ...`) |
| New 3-CP cluster provisioned | ✅ `nkp-harsh-test` — 3 control-plane / 2 workers, Rocky Linux 9.7 |
| `--move-leader` flag | ✅ Deployed |
| `runAsUser: 0` fix | ✅ Deployed |
| End-to-end 3-member defrag with leader transfer | ✅ **`manual-defrag-demo-1780310595` — full leader-safe flow succeeded** |
| Total etcd disk space reclaimed | **~229 MiB** (3 members combined) |
| Cluster availability during defrag | Uninterrupted — leadership moved before defragging the leader |
| Phase 3 (Kommander catalog app) | ✅ **Complete** — catalog app shipped to `nkp-nutanix-product-catalog/applications/nkp-etcd-maintenance/0.3.0` under the Flux/Kustomize pattern. Pending only live-cluster validation. |
| Phase 5 (Snapshot MVP) | 🟡 **In progress** — chart implementation done (`templates/snapshot-cronjob.yaml`, fail-fast invariants, catalog defaults bumped to 0.3.0). Pending: live-cluster validation against a real S3 endpoint. Design in `LLD-phase5.md`. |
| Phase Observability | ✅ **Complete** chart-side — `templates/prometheusrule.yaml` (8 alerts, capability-gated), logfmt upload-script logs, README + this doc's §9 playbook. Pending: live-cluster validation of alert firing. Design in `LLD-phase-observability.md`. |

**Validated run (manual-defrag-demo-1780310595, 2026-06-01 10:43 UTC):**

```
10:43:22  Health check: all 3 endpoints healthy
10:43:22  Compaction at revision 168964 — successful
10:43:22  3 endpoint(s) need to be defragmented
10:43:22  Defragmenting https://10.22.202.156:2379 (member 48b7c7…)
          dbSize 124,596,224 → 37,789,696    (took 367.8 ms)
10:43:22  Waiting 1m0s for next operation
10:44:22  Defragmenting https://10.22.202.157:2379 (member eb6678…)
          dbSize 120,553,472 → 41,865,216    (took 457.0 ms)
10:44:23  Waiting 1m0s for next operation
10:45:23  Transferring leadership f19b7f… → 48b7c7…   ← leader-safe step
10:45:23  Transferred the leadership successfully! Waiting 1m0s
10:46:23  Defragmenting https://10.22.202.161:2379 (former leader f19b7f…)
          dbSize 124,575,744 → 49,664,000    (took 2.53 s)
10:46:26  The defragmentation is successful.
```

Total reclaimed: ~229 MiB. Total runtime: ~3m4s.

**Next action — Phase 3:** package this chart as a Kommander catalog application.
See `LLD-phase3.md` and `kommander/` directory.

---

## Table of Contents

1. [Chart Validation (Local, No Cluster)](#1-chart-validation-local-no-cluster)
2. [Retrieving the Cluster Kubeconfig](#2-retrieving-the-cluster-kubeconfig)
3. [Verifying Cluster Connectivity](#3-verifying-cluster-connectivity)
4. [Installing the Chart](#4-installing-the-chart)
5. [Post-Install Verification](#5-post-install-verification)
6. [Day-2 Operations](#6-day-2-operations)
7. [Uninstalling the Chart](#7-uninstalling-the-chart)
8. [Phase 5 — Snapshot MVP Commands](#8-phase-5--snapshot-mvp-commands)
   - 8.1 Create the S3 credentials Secret
   - 8.2 Enable the snapshot CronJob
   - 8.3 Verify the install rendered correctly
   - 8.4 Trigger a one-shot manual snapshot
   - 8.5 Inspect per-container logs
   - 8.6 Verify the object landed in the bucket
   - 8.7 Disable the snapshot CronJob
   - 8.8 Troubleshooting
   - 8.9 **Manual Restore — concrete command sequence**
9. [Observability — Inspecting Jobs and Reading Failures](#9-observability--inspecting-jobs-and-reading-failures)
   - 9.1 Did the last run succeed?
   - 9.2 Why did it fail? (Events first, then logs)
   - 9.3 Reading the structured log lines
   - 9.4 Inspect the PrometheusRule and confirm Prometheus has loaded it
   - 9.5 Per-alert triage one-liners

---

## 1. Chart Validation (Local, No Cluster)

These commands run entirely on your local machine and do **not** require a
live Kubernetes cluster. They should be run first, before touching any cluster.

---

### `helm template`

```bash
helm template nkp-etcd-maintenance ./nkp-etcd-maintenance
```

**What it does:**
Renders all Helm templates in `./nkp-etcd-maintenance` using the default
values from `values.yaml` and prints the resulting Kubernetes YAML to stdout.
No resources are created anywhere.

**Why:**
This is the fastest way to inspect exactly what manifests Helm will send to
the API server. It catches template syntax errors (bad `{{ }}` expressions,
missing pipes, wrong indentation) before you involve a cluster.

**Expected output:**
Three YAML documents separated by `---`:
1. `ServiceAccount` (nkp-etcd-maintenance-sa)
2. `ClusterRole` + `ClusterRoleBinding` (nkp-etcd-maintenance-role / rolebinding)
3. `CronJob` (nkp-etcd-defrag) with all args rendered from values

**Useful variants:**

```bash
# Render with a non-default value to preview how overrides look
helm template nkp-etcd-maintenance ./nkp-etcd-maintenance \
  --set defragmentation.schedule="0 3 * * 0"

# Write the full manifest to a file for code review or GitOps
helm template nkp-etcd-maintenance ./nkp-etcd-maintenance \
  > rendered-manifest.yaml
```

---

### `helm lint`

```bash
helm lint ./nkp-etcd-maintenance
```

**What it does:**
Runs Helm's built-in linter against the chart directory. It checks:
- `Chart.yaml` is valid and has required fields (`name`, `version`, `apiVersion`)
- All template files parse without syntax errors
- `values.yaml` is valid YAML
- No obvious misconfigurations (missing required keys, wrong types)

**Why:**
`helm template` only catches rendering errors. `helm lint` additionally
validates chart metadata and catches structural issues that would silently
produce broken manifests.

**Expected output:**
```
==> Linting ./nkp-etcd-maintenance
[INFO] Chart.yaml: icon is recommended

1 chart(s) linted, 0 chart(s) failed
```

The `icon` INFO is cosmetic — it is only relevant if the chart is published
to a chart repository with a UI. It does not affect functionality.

**Exit codes:**
- `0` — no errors (warnings/infos are acceptable)
- `1` — one or more errors found; do not proceed to install

---

## 2. Retrieving the Cluster Kubeconfig

The NKP cluster's API server is not publicly exposed, so the admin kubeconfig
must be pulled from the control-plane node. The steps below document the exact
sequence used in this project.

---

### SSH into the control-plane node

```bash
ssh -i ~/.ssh/id_ed25519 konvoy@<control-plane-ip>
```

**What it does:**
Opens an interactive SSH session to the NKP control-plane node using an
Ed25519 private key for authentication. The `konvoy` user is the default
system account on NKP nodes.

**Why:**
The `admin.conf` kubeconfig lives on the control-plane node at
`/etc/kubernetes/admin.conf` and is readable only by `root`. We need to
copy it out to a location the `konvoy` user can read before transferring
it to the local machine.

---

### Copy `admin.conf` to a readable location on the node

```bash
sudo cp /etc/kubernetes/admin.conf /home/konvoy/admin.conf
```

**What it does:**
Uses `sudo` to copy the root-owned kubeconfig from its kubeadm-managed
location to the `konvoy` home directory.

**Why:**
`scp` and `cat` over SSH run as the authenticated user (`konvoy`), which
cannot read `/etc/kubernetes/admin.conf` directly. Making a copy in
`/home/konvoy/` gives that user access.

---

### Fix file ownership

```bash
sudo chown konvoy /home/konvoy/admin.conf
```

**What it does:**
Changes the owner of the copied file from `root` to `konvoy`.

**Why:**
After `sudo cp`, the file is owned by `root:root`. Without changing
ownership, the `konvoy` user cannot read it (the file permissions from
`admin.conf` are typically `0600`).

> **Note:** `sudo chown konvoy:konvoy` failed on this node because the
> `konvoy` group does not exist; specifying only the user (`konvoy`) is
> sufficient.

---

### Exit the SSH session

```bash
exit
```

**What it does:**
Closes the SSH session and returns to the local shell.

---

### Transfer the kubeconfig to your local machine

```bash
ssh -i ~/.ssh/id_ed25519 konvoy@<control-plane-ip> \
  "cat /home/konvoy/admin.conf" > ~/nkp-test-kubeconfig.yaml
```

**What it does:**
Runs `cat /home/konvoy/admin.conf` non-interactively on the remote node
over SSH and redirects the output into a local file
`~/nkp-test-kubeconfig.yaml`.

**Why `ssh … "cat …"` instead of `scp`:**
Direct `scp` failed in this environment (`subsystem request failed on
channel 0`) because the SSH server's sftp subsystem was not enabled.
The `cat`-over-SSH pattern bypasses sftp entirely and only requires a
working SSH connection.

**What the file contains:**
A standard kubeconfig with:
- `clusters` — the API server URL (`https://<ip>:6443`) and its CA certificate
- `users` — a client certificate + private key for the `kubernetes-admin` user
- `contexts` — binding the cluster and user together
- `current-context` — set to `kubernetes-admin@nkp-harsh-test-dev-41`

> **Security:** This file contains a client private key and grants full
> cluster-admin access. Treat it like a password — do not commit it to
> version control.

---

## 3. Verifying Cluster Connectivity

---

### Set the kubeconfig environment variable

```bash
export KUBECONFIG=~/nkp-test-kubeconfig.yaml
```

**What it does:**
Sets the `KUBECONFIG` environment variable for the current shell session.
All subsequent `kubectl` and `helm` commands in this session will
authenticate using this file instead of the default `~/.kube/config`.

**Why:**
This avoids overwriting your default kubeconfig and keeps the NKP cluster
credentials scoped to the current terminal session. Opening a new terminal
will not have this cluster configured unless you export again.

**Permanent alternative (if you always want this cluster active):**
```bash
# Merge the NKP config into your default kubeconfig
KUBECONFIG=~/.kube/config:~/nkp-test-kubeconfig.yaml \
  kubectl config view --flatten > /tmp/merged.yaml && \
  mv /tmp/merged.yaml ~/.kube/config
```

---

### Verify node connectivity

```bash
kubectl get nodes
```

**What it does:**
Queries the Kubernetes API server for the list of all nodes in the cluster
and prints their name, status, role, age, and Kubernetes version.

**Why:**
This is the canonical "is my kubeconfig working?" check. A successful
response proves that:
1. The API server is reachable at the address in the kubeconfig.
2. The client certificate is valid and accepted by the server.
3. The `kubernetes-admin` ClusterRole binding is in place.

**Expected output for this cluster:**
```
NAME                                            STATUS   ROLES           AGE     VERSION
nkp-harsh-test-dev-41-8csgk-gr47q              Ready    control-plane   2d18h   v1.35.2
nkp-harsh-test-dev-41-md-0-tsqwt-hfgdf-d827c   Ready    <none>          2d18h   v1.35.2
nkp-harsh-test-dev-41-md-0-tsqwt-hfgdf-rqjgp   Ready    <none>          2d18h   v1.35.2
```

One control-plane node (where etcd runs) and two worker nodes. The CronJob
will only be scheduled on the node with `ROLES: control-plane`.

---

## 4. Installing the Chart

---

### Install (or upgrade) the chart

```bash
helm upgrade --install nkp-etcd-maintenance ./nkp-etcd-maintenance \
  --namespace kube-system
```

**What it does:**
This is a single idempotent command that:
- **If the release does not exist** — performs a fresh `helm install`
- **If the release already exists** — performs a `helm upgrade` to apply
  any changes

`./nkp-etcd-maintenance` is the path to the chart directory on your local
machine (Helm reads and packages the chart on the fly without publishing it).

`--namespace kube-system` deploys all namespaced resources (`ServiceAccount`,
`CronJob`) into `kube-system`. The `ClusterRole` and `ClusterRoleBinding` are
cluster-scoped and are not affected by this flag.

**Why `kube-system`:**
The etcd process runs as a system component. Its client certificates are
owned by `root` with `0600` permissions. Only pods running on the
control-plane node with `hostNetwork: true` can reach `127.0.0.1:2379`.
Placing the job in `kube-system` groups it with other system-level workloads
and is the conventional namespace for such jobs on kubeadm clusters.

**Expected output:**
```
Release "nkp-etcd-maintenance" does not exist. Installing it now.
NAME: nkp-etcd-maintenance
LAST DEPLOYED: Thu May 28 10:24:48 2026
NAMESPACE: kube-system
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
TEST SUITE: None
```

**Common overrides at install time:**

```bash
# Use a different schedule (every Sunday at 03:00 UTC)
helm upgrade --install nkp-etcd-maintenance ./nkp-etcd-maintenance \
  --namespace kube-system \
  --set defragmentation.schedule="0 3 * * 0"

# Raise the defrag threshold (only defrag when >80% quota used)
helm upgrade --install nkp-etcd-maintenance ./nkp-etcd-maintenance \
  --namespace kube-system \
  --set defragmentation.defragRule="dbQuotaUsage > 0.8"

# Use a custom values file (recommended for multiple overrides)
helm upgrade --install nkp-etcd-maintenance ./nkp-etcd-maintenance \
  --namespace kube-system \
  -f my-custom-values.yaml

# Temporarily disable without uninstalling
helm upgrade nkp-etcd-maintenance ./nkp-etcd-maintenance \
  --namespace kube-system \
  --set defragmentation.enabled=false
```

---

## 5. Post-Install Verification

Run these commands after installing to confirm the chart deployed correctly.

---

### List installed Helm releases

```bash
helm ls -n kube-system
```

**What it does:**
Lists all Helm releases installed in the `kube-system` namespace, showing
the release name, namespace, revision number, last deployment timestamp,
status, chart name, and app version.

**Expected output:**
```
NAME                    NAMESPACE    REVISION  UPDATED              STATUS    CHART                         APP VERSION
nkp-etcd-maintenance    kube-system  1         2026-05-28 10:24:48  deployed  nkp-etcd-maintenance-0.1.0   v0.40.0
```

---

### Verify the CronJob was created

```bash
kubectl get cronjob -n kube-system nkp-etcd-defrag
```

**What it does:**
Queries the API server for the `nkp-etcd-defrag` CronJob in `kube-system`
and prints its schedule, suspension status, active run count, and last
schedule time.

**Expected output:**
```
NAME               SCHEDULE     SUSPEND   ACTIVE   LAST SCHEDULE   AGE
nkp-etcd-defrag    30 2 * * *   False     0        <none>          2m
```

`LAST SCHEDULE: <none>` is correct immediately after install — no run has
fired yet.

---

### Verify RBAC resources

```bash
kubectl get serviceaccount,clusterrole,clusterrolebinding \
  -n kube-system \
  -l app.kubernetes.io/name=nkp-etcd-maintenance
```

**What it does:**
Lists the `ServiceAccount` (namespaced) and the `ClusterRole` +
`ClusterRoleBinding` (cluster-scoped, but filterable by label) that belong
to this chart.

**Expected output:**
```
NAME                                          SECRETS   AGE
serviceaccount/nkp-etcd-maintenance-sa        0         3m

NAME                                                           CREATED AT
clusterrole.rbac.authorization.k8s.io/nkp-etcd-maintenance-role   2026-05-28T04:54:48Z

NAME                                                                      ROLE                                    AGE
clusterrolebinding.rbac.authorization.k8s.io/nkp-etcd-maintenance-rolebinding   ClusterRole/nkp-etcd-maintenance-role   3m
```

---

### Trigger a manual defrag run (without waiting for the cron schedule)

```bash
kubectl create job --from=cronjob/nkp-etcd-defrag \
  manual-defrag-$(date +%s) \
  -n kube-system
```

**What it does:**
Immediately creates a one-off `Job` using the pod template from the
`nkp-etcd-defrag` CronJob. The `$(date +%s)` suffix appends the current
Unix timestamp to make the job name unique so you can run this multiple
times without name collisions.

**Why:**
The CronJob's default schedule fires at 02:30 UTC. This command lets you
test the actual defrag logic on demand, which is essential for validating
the chart on a real cluster before relying on the scheduled run.

**Actual output from this session:**
```
job.batch/manual-defrag-1779949530 created
```

The job name `manual-defrag-1779949530` is the real name to use in all
follow-up commands below.

---

### Get the name of the most recently created defrag job

```bash
kubectl get jobs -n kube-system
```

**What it does:**
Lists all Jobs in `kube-system`. Use this to get the exact job name before
running `kubectl logs` or `kubectl describe`. You will see your manual job
alongside any other system jobs.

**Actual output from this session:**
```
NAME                               STATUS     COMPLETIONS   DURATION   AGE
hubble-generate-certs-68b052df61   Complete   1/1           92s        2d20h
manual-defrag-1779949530           ...
```

`hubble-generate-certs-*` is a Cilium/Hubble internal job for TLS
certificate rotation — it is unrelated to etcd maintenance and can be
ignored.

**Tip — capture the job name into a variable so you don't have to type it:**
```bash
JOB=$(kubectl get jobs -n kube-system \
  --sort-by=.metadata.creationTimestamp \
  -o jsonpath='{.items[-1].metadata.name}')
echo $JOB   # e.g. manual-defrag-1779949530
```

---

### Watch the job pod and follow its logs

```bash
# Capture the job name first (see above)
JOB=$(kubectl get jobs -n kube-system \
  --sort-by=.metadata.creationTimestamp \
  -o jsonpath='{.items[-1].metadata.name}')

# Watch the pod state transitions (Ctrl+C when Completed)
kubectl get pods -n kube-system -l job-name=$JOB -w

# Stream the container logs
kubectl logs -n kube-system -l job-name=$JOB --follow
```

**What it does:**
`kubectl get pods -w` enters watch mode and prints a new line every time
the pod's state changes (Pending → ContainerCreating → Running → Completed).

`kubectl logs --follow` streams stdout/stderr from the `etcd-defrag`
container in real time. The tool prints a line for each etcd member it
processes, whether the defrag rule passed, and the before/after db sizes.

> **Common mistake:** Do **not** type `job-name=manual-defrag-<timestamp>`
> literally. In `zsh`/`bash`, `<timestamp>` is interpreted as an input
> redirection operator and the shell will error with
> `zsh: no such file or directory: timestamp`. Always substitute the real
> job name or use the `$JOB` variable pattern above.

**What healthy log output looks like:**
```
[2026-05-28 04:55:12] INFO: checking cluster health before defragmentation
[2026-05-28 04:55:12] INFO: cluster is healthy, proceeding
[2026-05-28 04:55:12] INFO: [endpoint https://127.0.0.1:2379] evaluating defrag rule
[2026-05-28 04:55:12] INFO: defrag rule is true, starting defragmentation
[2026-05-28 04:55:13] INFO: defragmented endpoint https://127.0.0.1:2379
  db size before: 45 MB → after: 28 MB
```

---

### Inspect a completed job

```bash
kubectl describe job -n kube-system $JOB
```

**What it does:**
Prints detailed information about the Job object: the pod template spec,
start/completion timestamps, number of succeeded/failed pods, and any
events emitted during the run (e.g., scheduling failures, image pull errors).

---

## 6. Day-2 Operations

---

### Check the history of scheduled runs

```bash
kubectl get jobs -n kube-system \
  -l app.kubernetes.io/name=nkp-etcd-maintenance \
  --sort-by=.metadata.creationTimestamp
```

**What it does:**
Lists all Job objects created by the CronJob, sorted oldest-first by
creation time. Each scheduled tick creates one Job; the CronJob retains
the last 3 successful and 3 failed jobs (configurable via
`successfulJobsHistoryLimit` / `failedJobsHistoryLimit` in `values.yaml`).

---

### View the full CronJob spec as applied to the cluster

```bash
kubectl get cronjob nkp-etcd-defrag -n kube-system -o yaml
```

**What it does:**
Retrieves the live CronJob resource from the cluster and prints it as
YAML. This shows the exact spec that the API server stored, including any
defaulted fields that Helm did not set explicitly. Useful for auditing.

---

### Check Helm release history

```bash
helm history nkp-etcd-maintenance -n kube-system
```

**What it does:**
Shows every revision of the `nkp-etcd-maintenance` Helm release — the
revision number, timestamp, status, chart version, and the description
(Install complete / Upgrade complete / Rollback to …).

---

### Roll back to a previous revision

```bash
helm rollback nkp-etcd-maintenance <revision-number> -n kube-system
```

**What it does:**
Re-applies the manifests from the specified revision, effectively
reverting the chart to that state. Helm records this as a new revision
(incremented) so the history is preserved.

**When to use:**
If an upgrade changed a value (e.g., the schedule or defrag rule) that
caused issues, roll back to the last known-good revision.

---

## 7. Uninstalling the Chart

```bash
helm uninstall nkp-etcd-maintenance --namespace kube-system
```

**What it does:**
Deletes all Kubernetes resources that were created by the
`nkp-etcd-maintenance` Helm release:

| Resource | Kind | Scope |
|---|---|---|
| `nkp-etcd-maintenance-sa` | ServiceAccount | Namespaced (kube-system) |
| `nkp-etcd-maintenance-role` | ClusterRole | Cluster-scoped |
| `nkp-etcd-maintenance-rolebinding` | ClusterRoleBinding | Cluster-scoped |
| `nkp-etcd-defrag` | CronJob | Namespaced (kube-system) |

**What it does NOT delete:**
- Job pods from past runs (they were created by the CronJob controller,
  not directly by Helm). Clean them up manually if needed:
  ```bash
  kubectl delete jobs -n kube-system \
    -l app.kubernetes.io/name=nkp-etcd-maintenance
  ```
- The `~/nkp-test-kubeconfig.yaml` file on your local machine.
- The `admin.conf` copy left in `/home/konvoy/` on the control-plane node.

---

## Known Issues & Fixes

### `permission denied` on `server.key` (discovered 2026-05-29, resolved after two attempts)

**Symptom:**
Job pods `manual-defrag-1780027602` and `manual-defrag-1780031229` both landed
on the correct control-plane node (`nkp-harsh-test-dev-41-8csgk-gr47q`) with
`--move-leader` working, but failed at:
```
Failed to get members' health info: open /etc/kubernetes/pki/etcd/server.key: permission denied
```

**Investigation — two hypotheses:**

**Attempt 1 (wrong):** Suspected `capabilities.drop: [ALL]` was removing
`DAC_OVERRIDE`, preventing a root container from reading a non-root-owned file.
Fix: removed `capabilities.drop: [ALL]`. Error persisted on next run.

**Root cause (correct — Attempt 2):** `runAsNonRoot: false` was misread as
"the container runs as root". It is not — it only disables Kubernetes' admission
check that rejects root containers. It does NOT set the container UID.

The actual UID comes from the `USER` instruction in the image's Dockerfile.
`ghcr.io/ahrtr/etcd-defrag` uses a non-root USER (distroless images default
to UID `65532`). On the host, `server.key` is `0600 root:root`:

| Field | Value |
|---|---|
| File owner | UID 0 (root) |
| File permissions | `0600` (owner read/write only) |
| Container UID (before fix) | `65532` (image default) |
| Result | UID 65532 ≠ owner → no permission → denied |

**The distinction that matters:**

| Setting | What it actually does |
|---|---|
| `runAsNonRoot: false` | Disables the Kubernetes check that *blocks* root containers. Does NOT set UID to 0. |
| `runAsUser: 0` | Explicitly overrides the image's USER instruction. Forces process UID to 0. Reads `0600 root:root` files. |

**Fix applied:**
Added `runAsUser: 0` to the securityContext. Removed `runAsNonRoot: false`
(no longer needed once `runAsUser: 0` is set — Kubernetes won't block it).

**Resolution — run these commands:**
```bash
helm upgrade nkp-etcd-maintenance ./nkp-etcd-maintenance --namespace kube-system

kubectl create job --from=cronjob/nkp-etcd-defrag \
  manual-defrag-$(date +%s) -n kube-system

JOB=$(kubectl get jobs -n kube-system \
  --sort-by=.metadata.creationTimestamp \
  -o jsonpath='{.items[-1].metadata.name}')
kubectl logs -n kube-system -l job-name=$JOB --follow
```

---

### `Error: unknown flag: --leader-last` (discovered 2026-05-28)

**Symptom:**
The job pod `manual-defrag-1779949530` started but exited immediately with:
```
Error: unknown flag: --leader-last
```

**Root cause:**
The initial chart used `--leader-last=true` based on the internship brief's
proposed config shape, but this flag **does not exist in `v0.40.0`** of
`ahrtr/etcd-defrag`. The tool's actual help output reveals the correct
equivalent flag is `--move-leader`:

```
--move-leader   whether to move the leadership before performing
                defragmentation on the leader
```

`--move-leader` is a boolean flag (presence = enabled); it does not take
a `=true` value argument.

**Why `--move-leader` satisfies the "leader-last" requirement:**

The internship brief and Phase 1 design note both specify `leaderLast: true`
as a safety requirement to prevent cluster disruption during defragmentation.
`--move-leader` fulfils this with an even stronger guarantee:

| Approach | Behaviour |
|---|---|
| Leader-last ordering | Defrags all followers first, then defrags the current leader (leader is still leader during its own defrag) |
| `--move-leader` | When it is the leader's turn, first transfers leadership to another member, *then* defrags the former leader |

With `--move-leader`, the cluster always has a healthy, non-defragging leader
throughout the entire maintenance window — including when the former-leader
is being compacted.

**Fix applied to chart on disk:**
1. `values.yaml` — the user-facing key remains `defragmentation.leaderLast`
   (matching the brief's API shape). Internally it maps to `--move-leader`.
2. `values.yaml` — added two missing values from the brief:
   `defragmentation.waitBetweenDefrags: "1m"` and `defragmentation.autoDisalarm: false`.
3. `templates/defrag-cronjob.yaml` — template updated for all three changes.

**Status: fix is on disk but NOT yet deployed to the cluster.**
The cluster is still running REVISION 1 (the broken version).

Run this to apply and validate:
```bash
# Deploy the fix (creates REVISION 2)
helm upgrade nkp-etcd-maintenance ./nkp-etcd-maintenance \
  --namespace kube-system

# Verify REVISION 2 is live
helm history nkp-etcd-maintenance -n kube-system

# Trigger a fresh test run
kubectl create job --from=cronjob/nkp-etcd-defrag \
  manual-defrag-$(date +%s) -n kube-system

# Follow logs — should now complete without errors
JOB=$(kubectl get jobs -n kube-system \
  --sort-by=.metadata.creationTimestamp \
  -o jsonpath='{.items[-1].metadata.name}')
kubectl logs -n kube-system -l job-name=$JOB --follow
```

---

## 8. Phase 5 — Snapshot MVP Commands

This section is the practical companion to [`LLD-phase5.md`](./LLD-phase5.md)
and the [Snapshot CronJob](./README.md#snapshot-cronjob-phase-5) section of
the README. Every command below has been validated locally with `helm template`
and `helm lint`; live-cluster validation is the next milestone.

### 8.1 — Create the S3 credentials Secret

The chart NEVER receives the access key or secret access key. They live
exclusively in a Kubernetes Secret in the chart's release namespace
(`kube-system` by default). Pick the example that matches your endpoint
type:

#### AWS S3

```bash
kubectl create secret generic etcd-backup-s3-creds \
  --namespace kube-system \
  --from-literal=access-key-id='AKIAEXAMPLEKEY' \
  --from-literal=secret-access-key='wJalrXUtnFEMI/K7MDENG/EXAMPLEKEY'
```

#### MinIO (self-hosted)

```bash
kubectl create secret generic etcd-backup-s3-creds \
  --namespace kube-system \
  --from-literal=access-key-id='minio-svc-account' \
  --from-literal=secret-access-key='minio-svc-secret'
```

#### Nutanix Objects

Generate object-store keys in Prism Central → Objects → Access Keys, then:

```bash
kubectl create secret generic etcd-backup-s3-creds \
  --namespace kube-system \
  --from-literal=access-key-id='<nutanix-objects-access-key>' \
  --from-literal=secret-access-key='<nutanix-objects-secret-key>'
```

#### Verify

```bash
kubectl get secret etcd-backup-s3-creds -n kube-system
# NAME                      TYPE     DATA   AGE
# etcd-backup-s3-creds      Opaque   2      3s

# Optional: confirm the two expected keys are present (values are base64'd).
kubectl get secret etcd-backup-s3-creds -n kube-system -o json \
  | jq '.data | keys'
# [ "access-key-id", "secret-access-key" ]
```

> **If you use different key names inside the Secret**, also pass
> `--set snapshot.s3.credentialsSecret.accessKeyKey=<your-name>` and
> `--set snapshot.s3.credentialsSecret.secretKeyKey=<your-name>` at install time.

### 8.2 — Enable the snapshot CronJob

Three install modes; pick one.

#### Mode A — Verify-only (no upload). Useful in CI / staging.

```bash
helm upgrade --install nkp-etcd-maintenance ./nkp-etcd-maintenance \
  --namespace kube-system \
  --set snapshot.enabled=true
```

The CronJob will run daily at 03:00 UTC, take a snapshot, verify it, then
discard it on Pod termination. Useful to confirm the snapshot path works
end-to-end before wiring up S3.

#### Mode B — Verify + upload to S3-compatible endpoint

```bash
helm upgrade --install nkp-etcd-maintenance ./nkp-etcd-maintenance \
  --namespace kube-system \
  --set snapshot.enabled=true \
  --set snapshot.s3.enabled=true \
  --set snapshot.s3.endpoint=https://minio.example.com \
  --set snapshot.s3.bucket=nkp-etcd-backups \
  --set snapshot.s3.credentialsSecret.name=etcd-backup-s3-creds
```

#### Mode C — Same as B, but with a custom schedule, prefix, and cluster name

```bash
helm upgrade --install nkp-etcd-maintenance ./nkp-etcd-maintenance \
  --namespace kube-system \
  --set snapshot.enabled=true \
  --set snapshot.schedule="0 */6 * * *" \
  --set snapshot.clusterName=prod-east-1 \
  --set snapshot.s3.enabled=true \
  --set snapshot.s3.endpoint=https://objects.nutanix.example.com \
  --set snapshot.s3.bucket=etcd-disaster-recovery \
  --set snapshot.s3.prefix=clusters \
  --set snapshot.s3.pathStyle=true \
  --set snapshot.s3.credentialsSecret.name=etcd-backup-s3-creds
```

This will produce object keys like:

```
clusters/prod-east-1-2026-06-09T03-00-12Z.db
clusters/prod-east-1-2026-06-09T09-00-15Z.db
clusters/prod-east-1-2026-06-09T15-00-09Z.db
clusters/prod-east-1-2026-06-09T21-00-11Z.db
```

### 8.3 — Verify the install rendered correctly

```bash
# Confirm both CronJobs exist
kubectl get cronjob -n kube-system | grep nkp-etcd
# nkp-etcd-defrag      30 2 * * *      ...
# nkp-etcd-snapshot    0 3 * * *       ...

# Inspect the snapshot CronJob's pod template (init containers + secret refs).
kubectl get cronjob nkp-etcd-snapshot -n kube-system -o yaml | \
  yq '.spec.jobTemplate.spec.template.spec |
      {initContainers: [.initContainers[].name],
       containers:     [.containers[].name],
       env:            (.containers[0].env // []) | map(.name)}'
```

You should see `initContainers: [take-snapshot, verify-snapshot]` and (in
S3-on mode) `env` containing `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`.

### 8.4 — Trigger a one-shot manual snapshot

```bash
# Manual run without waiting for the next cron tick:
kubectl create job --from=cronjob/nkp-etcd-snapshot \
  manual-snapshot-$(date +%s) -n kube-system

# Watch the Pod progress through its init containers:
POD=$(kubectl get pods -n kube-system \
  -l job-name=manual-snapshot-... \
  -o jsonpath='{.items[0].metadata.name}')
kubectl get pod $POD -n kube-system -w
```

Expected Pod phase transitions:
```
PodInitializing  (take-snapshot running)
PodInitializing  (verify-snapshot running)
Running          (upload running, S3-on mode) OR
Completed        (noop running, S3-off mode)
Completed
```

### 8.5 — Inspect per-container logs

The snapshot Pod has up to 3 distinct containers. Each tells you about a
different phase:

```bash
POD=$(kubectl get pods -n kube-system \
  -l job-name=manual-snapshot-... \
  -o jsonpath='{.items[0].metadata.name}')

# Phase 1: did etcdctl write the snapshot file?
kubectl logs $POD -n kube-system -c take-snapshot
# Expected:
#   {"level":"info","msg":"created temporary db file",...}
#   {"level":"info","msg":"fetching snapshot","endpoint":"https://127.0.0.1:2379"}
#   {"level":"info","msg":"saved","path":"/snapshot/etcd.db"}

# Phase 2: did etcdutl confirm the file is valid?
kubectl logs $POD -n kube-system -c verify-snapshot
# Expected: a one-line table:
#   +----------+----------+------------+------------+
#   |   HASH   | REVISION | TOTAL KEYS | TOTAL SIZE |
#   +----------+----------+------------+------------+
#   | abc12345 |   168972 |       1234 |    78 MB   |
#   +----------+----------+------------+------------+

# Phase 3 (S3-on only): did mc upload?
kubectl logs $POD -n kube-system -c upload
# Expected (logfmt — every line starts with [upload] phase=<name>):
#   [upload] phase=start ts=2026-06-09T03-00-12Z target_bucket=nkp-etcd-backups target_key=etcd-snapshots/<cluster>-<ts>.db
#   [upload] phase=alias-set endpoint=https://minio.example.com path-style=on api=S3v4
#   Added `target` successfully.
#   [upload] phase=copy source=/snapshot/etcd.db
#   `/snapshot/etcd.db` -> `target/nkp-etcd-backups/...db`  (76.3 MiB/76.3 MiB)
#   [upload] phase=success bytes_uploaded=80104448 wall_clock_seconds=8
#
# On failure, exactly one line of the form:
#   [upload] phase=alias-set-failed exit_code=1
#   [upload] phase=copy-failed exit_code=1
# is emitted immediately before the container exits non-zero.
```

### 8.6 — Verify the object landed in the bucket (mc / aws)

From your workstation (NOT the cluster):

```bash
# With mc:
mc alias set check https://minio.example.com <ACCESS_KEY> <SECRET_KEY> --path on
mc ls --recursive check/nkp-etcd-backups/etcd-snapshots/ | tail -5

# With AWS CLI:
aws --endpoint-url https://minio.example.com s3 ls \
  s3://nkp-etcd-backups/etcd-snapshots/ --recursive | tail -5
```

### 8.7 — Disable the snapshot CronJob (without uninstalling the chart)

```bash
helm upgrade nkp-etcd-maintenance ./nkp-etcd-maintenance \
  --namespace kube-system \
  --reuse-values \
  --set snapshot.enabled=false
```

This removes the `nkp-etcd-snapshot` CronJob; the defrag CronJob is untouched.

### 8.8 — Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `helm upgrade` fails with `snapshot.s3.endpoint is empty` | You set `s3.enabled=true` but didn't pass a required field. | Pass `endpoint`, `bucket`, and `credentialsSecret.name`. |
| `take-snapshot` exits with `connection refused` | etcd is not on `127.0.0.1:2379` (uncommon NKP topology). | Confirm via `ss -tlnp \| grep 2379` on a CP node. |
| `take-snapshot` exits with `open /etc/kubernetes/pki/etcd/server.key: permission denied` | `runAsUser` was overridden to non-root. | Don't override; the chart already sets `runAsUser: 0`. |
| `verify-snapshot` fails after `take-snapshot` succeeded | Snapshot got corrupted during write (rare; usually disk full). | Check `df -h /var/lib/kubelet` on the CP node; inspect `take-snapshot` logs for ENOSPC. |
| `upload` fails with `x509: certificate signed by unknown authority` | Self-signed cert on the S3 endpoint. | Set `--set snapshot.s3.insecureSkipTLSVerify=true` (lab only) or install the CA on the node. |
| `upload` fails with `Access Denied (403)` | Wrong key, wrong region, or bucket policy blocks the user. | Verify with `mc` from your workstation; check bucket IAM. |
| Object key not what you expected | `snapshot.clusterName` defaulted to the Helm release name. | Set `--set snapshot.clusterName=<name>` explicitly. |

### 8.9 — Manual Restore — concrete command sequence

> **READ FIRST**: see the full
> [Manual Restore Runbook](./README.md#manual-restore-runbook) in the README.
> The block below is the literal command sequence; do not run it without
> understanding the runbook's pre-flight checklist.

```bash
# --- On your workstation: fetch the snapshot to restore ---
mc cp check/nkp-etcd-backups/etcd-snapshots/<cluster>-<ts>.db ./restore.db
etcdutl snapshot status restore.db -w table   # sanity check

# Copy to every CP node (substitute IPs):
for IP in 10.22.202.156 10.22.202.157 10.22.202.161; do
  scp restore.db root@$IP:/root/etcd.db
done

# --- On EACH CP node, as root ---
systemctl stop kubelet
mv /var/lib/etcd /var/lib/etcd.broken-$(date +%s)

# Choose NODE_NAME / NODE_IP for THIS node:
NODE_NAME=cp1
NODE_IP=10.22.202.156

# Initial-cluster string MUST be identical on every node:
INITIAL_CLUSTER="cp1=https://10.22.202.156:2380,cp2=https://10.22.202.157:2380,cp3=https://10.22.202.161:2380"

etcdutl snapshot restore /root/etcd.db \
  --name=$NODE_NAME \
  --initial-cluster=$INITIAL_CLUSTER \
  --initial-cluster-token=etcd-cluster \
  --initial-advertise-peer-urls=https://$NODE_IP:2380 \
  --data-dir=/var/lib/etcd

chmod -R 700 /var/lib/etcd
systemctl start kubelet

# --- After all CP nodes are restarted: validate from workstation ---
kubectl get nodes
kubectl -n kube-system exec etcd-cp1 -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint status -w table
```

If anything fails, the original (broken) data dir is at
`/var/lib/etcd.broken-<timestamp>` on every node. Stop kubelet, move it
back, restart kubelet, and engage support.

---

## 9. Observability — Inspecting Jobs and Reading Failures

This section is the operator-side companion to the chart's three
observability signals (native Events, structured logs, PrometheusRule
alerts). Design rationale lives in
[`LLD-phase-observability.md`](./LLD-phase-observability.md); per-alert
runbook entries are in
[`README.md` — Observability](./README.md#observability--events-logs-alerts).

### 9.1 — Did the last run succeed?

The fastest health check uses native CronJob status — no `helm`, no
exec into a pod required.

```bash
# Are the CronJobs scheduling? LAST SCHEDULE column is the canonical signal.
kubectl get cronjob -n kube-system \
  -l app.kubernetes.io/name=nkp-etcd-maintenance
# Expected:
#   NAME                 SCHEDULE      SUSPEND   ACTIVE   LAST SCHEDULE   AGE
#   nkp-etcd-defrag      30 2 * * *    False     0        7h12m           14d
#   nkp-etcd-snapshot    0 3 * * *     False     0        6h42m           14d
#
# Red flags:
#   SUSPEND=True            → someone disabled it; resume with `kubectl patch`.
#   ACTIVE>0 for hours      → a Job is stuck; see 9.2.
#   LAST SCHEDULE more than
#     `missedScheduleSeconds` old → EtcdDefragJobMissed will fire soon.
```

```bash
# Did the most recent Job complete successfully?
kubectl get jobs -n kube-system \
  -l app.kubernetes.io/name=nkp-etcd-maintenance \
  --sort-by=.metadata.creationTimestamp | tail -10
# COMPLETIONS column should be "1/1" for healthy runs.
# A Job in "0/1" state for more than its `for: 5m` window is the trigger
# behind EtcdDefragJobFailed / EtcdSnapshotJobFailed.
```

```bash
# CronJob status, in YAML, with the last successful/failed times:
kubectl get cronjob nkp-etcd-defrag -n kube-system \
  -o jsonpath='{.status}' | jq
# {
#   "lastScheduleTime":   "2026-06-12T02:30:00Z",
#   "lastSuccessfulTime": "2026-06-12T02:33:04Z",
#   ...
# }
```

### 9.2 — Why did it fail? (Events first, then logs)

The native Job controller emits Events for every state transition. **Events
explain WHY** (image pull failed, scheduling failed, node tainted,
backoff exceeded); **logs explain WHAT** (the binary's stderr).

#### Step 1 — Get the failed Job's name

```bash
JOB=$(kubectl get jobs -n kube-system \
  -l app.kubernetes.io/name=nkp-etcd-maintenance \
  --field-selector=status.successful=0 \
  --sort-by=.metadata.creationTimestamp \
  -o jsonpath='{.items[-1].metadata.name}')
echo "$JOB"
# nkp-etcd-defrag-29103420   OR   manual-defrag-1780310595
```

#### Step 2 — Read the Events (the "WHY")

```bash
kubectl describe job "$JOB" -n kube-system
```

Look at the **Events:** table at the bottom. The signals you want:

| Event reason | What it means | What to do |
|---|---|---|
| `SuccessfulCreate` only | Pod started fine; failure is inside the container. | Skip to §9.2 step 3 (logs). |
| `FailedCreate` | API server rejected the Pod (RBAC, quota, admission). | Read the message; usually a quota or PSP/PSA violation. |
| `BackoffLimitExceeded` | The Pod kept retrying and gave up. With our `backoffLimit: 0`, this should be **rare** — it means CronJob.spec.backoffLimit was overridden. | Inspect the Pod's own Events. |
| `DeadlineExceeded` | `activeDeadlineSeconds` (if set) was reached. | Snapshot defaults are 5 min — usually a hung S3 upload. |

For Pod-level Events (one level deeper):

```bash
POD=$(kubectl get pods -n kube-system -l job-name="$JOB" \
  -o jsonpath='{.items[0].metadata.name}')
kubectl describe pod "$POD" -n kube-system | sed -n '/^Events:/,$p'
```

Common Pod-level events:

| Event reason | What it means |
|---|---|
| `FailedScheduling` | No control-plane node available; check `kubectl get nodes` for `NotReady` or tainted control planes. |
| `Failed` with `ImagePullBackOff` | Air-gapped cluster needs `image.repository` / `imagePullSecrets`. |
| `Failed` with `Error` and `ExitCode != 0` | Container ran but errored — go to logs. |

#### Step 3 — Read the logs (the "WHAT")

```bash
# Easiest: dump every container's stdout/stderr with a per-line prefix
kubectl logs job/"$JOB" -n kube-system --all-containers --prefix --tail=200
# Each line is prefixed [pod/<pod>/<container>] so init containers and
# main containers stay attributable.

# Tail a single container (init containers are addressable directly):
POD=$(kubectl get pods -n kube-system -l job-name="$JOB" \
  -o jsonpath='{.items[0].metadata.name}')
kubectl logs "$POD" -n kube-system -c take-snapshot     # snapshot phase 1
kubectl logs "$POD" -n kube-system -c verify-snapshot   # snapshot phase 2
kubectl logs "$POD" -n kube-system -c upload            # snapshot phase 3 (S3-on only)
kubectl logs "$POD" -n kube-system -c etcd-defrag       # defrag (single container)
```

> If a Pod has already been garbage-collected (`ttlSecondsAfterFinished`
> elapsed), `kubectl logs` will return "No resources found". The Job's
> Events survive longer; use `kubectl get events -n kube-system | grep <jobname>`
> as a fallback.

### 9.3 — Reading the structured log lines

#### Defrag (single container)

The `ahrtr/etcd-defrag` tool emits `key=value` log lines. The lines that
matter for triage:

```bash
kubectl logs job/"$JOB" -n kube-system | grep -E '^(Health check|Defragmenting|Transferring|The defragmentation)'
# Expected end-state:
#   Health check: all 3 endpoints healthy
#   Defragmenting https://10.22.202.156:2379 (member 48b7c7…) dbSize 124M → 37M (took 367 ms)
#   Defragmenting https://10.22.202.157:2379 (member eb6678…) dbSize 120M → 41M (took 457 ms)
#   Transferring leadership f19b7f… → 48b7c7…
#   Defragmenting https://10.22.202.161:2379 (former leader f19b7f…) dbSize 124M → 49M (took 2.53 s)
#   The defragmentation is successful.
```

#### Snapshot — `take-snapshot` (init)

`etcdctl snapshot save` emits upstream JSON. The success indicator:

```bash
kubectl logs "$POD" -n kube-system -c take-snapshot | grep '"saved"'
# {"level":"info","msg":"saved","path":"/snapshot/etcd.db"}
```

#### Snapshot — `verify-snapshot` (init)

`etcdutl snapshot status -w table` emits a one-line table. **A successful
run prints the table; a failed run prints a Go error.**

```bash
kubectl logs "$POD" -n kube-system -c verify-snapshot
# +----------+----------+------------+------------+
# |   HASH   | REVISION | TOTAL KEYS | TOTAL SIZE |
# +----------+----------+------------+------------+
# | abc12345 |   168972 |       1234 |    78 MB   |
# +----------+----------+------------+------------+
```

#### Snapshot — `upload` (main, S3-on only)

The upload script is the only chart-emitted log surface and uses **logfmt**
(`[upload] phase=<name> key=value …`). The phases are:

| Phase | When | Example |
|---|---|---|
| `phase=start` | once, at the top | `[upload] phase=start ts=2026-06-12T03-00-12Z target_bucket=nkp-etcd-backups target_key=etcd-snapshots/prod-2026-06-12T03-00-12Z.db` |
| `phase=alias-set` | before `mc alias set` | `[upload] phase=alias-set endpoint=https://minio.example.com path-style=on api=S3v4` |
| `phase=alias-set-failed` | error path only | `[upload] phase=alias-set-failed exit_code=1` |
| `phase=copy` | before `mc cp` | `[upload] phase=copy source=/snapshot/etcd.db` |
| `phase=copy-failed` | error path only | `[upload] phase=copy-failed exit_code=1` |
| `phase=success` | once, at the bottom | `[upload] phase=success bytes_uploaded=80104448 wall_clock_seconds=8` |

Greppable one-liners:

```bash
# Did upload succeed?
kubectl logs "$POD" -n kube-system -c upload | grep -q '^\[upload\] phase=success' \
  && echo OK || echo FAIL

# Why did it fail?
kubectl logs "$POD" -n kube-system -c upload | grep '^\[upload\] phase=.*failed'

# Extract bytes uploaded over time, for a quick capacity-planning sanity check
kubectl logs --tail=-1 -n kube-system -l app.kubernetes.io/name=nkp-etcd-maintenance \
  --max-log-requests=20 -c upload 2>/dev/null \
  | awk '/phase=success/ {for (i=1;i<=NF;i++) if ($i~/^bytes_uploaded=/) print $i}'
# bytes_uploaded=80104448
# bytes_uploaded=80104960
# ...
```

### 9.4 — Inspect the PrometheusRule and confirm Prometheus has loaded it

```bash
# Is the resource in the cluster?
kubectl get prometheusrule nkp-etcd-maintenance -n kube-system
# Expected:
#   NAME                    AGE
#   nkp-etcd-maintenance    14d

# If you get "No resources found", BOTH of these may be true:
#   1. alerts.enabled is false  → check `helm get values nkp-etcd-maintenance -n kube-system | grep -A1 alerts:`
#   2. Prometheus Operator CRD missing → check `kubectl get crd | grep prometheusrules.monitoring.coreos.com`
#
# If (2) is true, install the operator (e.g. via kube-prometheus-stack) and
# re-run `helm upgrade` to materialise the rule.

# Read the rule:
kubectl get prometheusrule nkp-etcd-maintenance -n kube-system -o yaml | \
  yq '.spec.groups[].rules[] | {alert: .alert, severity: .labels.severity, for: .for}'

# Confirm Prometheus's ruleSelector picks it up.
# Open the Prometheus UI → Status → Rules → search "nkp-etcd-maintenance".
# Expected rule count: 6 (defrag-only deploy) or 8 (snapshot also enabled).
```

If Prometheus's UI shows zero rules from `nkp-etcd-maintenance` even though
the resource exists, the Operator's `ruleSelector` doesn't match the labels
the chart applied. Inspect:

```bash
kubectl get prometheus -A \
  -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\t"}{.spec.ruleSelector}{"\n"}{end}'
```

Then re-render with the matching labels:

```bash
helm upgrade nkp-etcd-maintenance ./nkp-etcd-maintenance \
  --namespace kube-system --reuse-values \
  --set alerts.additionalLabels.<your-operator-label-key>=<value>
```

### 9.5 — Per-alert triage one-liners

Each row mirrors a section in
[`README.md` — Per-alert runbook](./README.md#per-alert-runbook). When an
alert fires, copy the matching block; it is the **first** command you
should run.

| Alert | First triage command |
|---|---|
| `EtcdMemberNoLeader` | `kubectl get pods -n kube-system -l component=etcd -o wide && kubectl logs -n kube-system etcd-<cp-node> --tail=200 \| grep -iE 'leader\|election'` |
| `EtcdDbHighUsage` | `kubectl logs -n kube-system <most-recent-defrag-pod> \| grep -E 'rule\|skipping\|Defragmenting'` |
| `EtcdDbCriticalUsage` | `kubectl create job --from=cronjob/nkp-etcd-defrag manual-defrag-emergency-$(date +%s) -n kube-system` |
| `EtcdHighFragmentation` | Same as `EtcdDbHighUsage`; consider lowering `defragmentation.defragRule`. |
| `EtcdDefragJobFailed` | `JOB=$(kubectl get jobs -n kube-system -l app.kubernetes.io/name=nkp-etcd-maintenance --field-selector=status.successful=0 --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}') && kubectl describe job "$JOB" -n kube-system && kubectl logs job/"$JOB" -n kube-system --all-containers --prefix` |
| `EtcdDefragJobMissed` | `kubectl get cronjob nkp-etcd-defrag -n kube-system && kubectl get cronjob nkp-etcd-defrag -n kube-system -o jsonpath='{.spec.suspend}'` |
| `EtcdSnapshotJobFailed` | Same as `EtcdDefragJobFailed`, but inspect each init container separately: `kubectl logs <pod> -n kube-system -c take-snapshot`, then `-c verify-snapshot`, then `-c upload`. |
| `EtcdSnapshotJobMissed` | Same as `EtcdDefragJobMissed`, but for `nkp-etcd-snapshot`. |

### 9.6 — Silence an alert temporarily (Alertmanager)

```bash
# Silence by alert name for 24 h
amtool silence add alertname=EtcdHighFragmentation \
  --duration=24h \
  --comment="defrag rule tuning in progress, ticket NKP-1234"

# Silence by job name (e.g. silence both defrag alerts during a planned
# CP maintenance window)
amtool silence add cronjob=nkp-etcd-defrag --duration=2h \
  --comment="planned CP node maintenance"

# List active silences
amtool silence query
```

For permanent suppression of a rule (e.g. operator already has their own
`EtcdMemberNoLeader`), prefer the chart-level disable so the rule never
hits Prometheus at all:

```bash
helm upgrade nkp-etcd-maintenance ./nkp-etcd-maintenance \
  --namespace kube-system --reuse-values \
  --set alerts.rules.EtcdMemberNoLeader.enabled=false
```

---

## 9.7 — Actively triggering the `etcd-health` alerts (chaos recipe)

Sections 9.1 – 9.6 cover **passive** observation: how to inspect alerts when
something has actually gone wrong. To **prove** the four `etcd-health`
alerts work end-to-end, you have to actively make them fire on a real
cluster, then clean up. **Live-validated on `nkp-harsh-test-2`, 2026-06-14**;
captured evidence under `docs/chaos/evidence/`.

The full step-by-step recipe lives in:

- [`docs/chaos/CHAOS-RECIPE.md`](docs/chaos/CHAOS-RECIPE.md) — narrative + safety rationale + Step 0 (the etcd-listen-flag prereq)
- [`docs/chaos/etcd-metrics-listen-fixer.yaml`](docs/chaos/etcd-metrics-listen-fixer.yaml) — one-time per-node fixer to make etcd reachable on the node IP
- [`docs/chaos/etcd-peer-partition.yaml`](docs/chaos/etcd-peer-partition.yaml) — the chaos partition Pod

**Important prereq** (the #1 gotcha discovered during live validation):
NKP/kubeadm defaults to `--listen-metrics-urls=http://127.0.0.1:2381` on
etcd, so kube-prometheus-stack's kubeEtcd targets are
`connection refused` and **no etcd-health alert can ever fire**. Step 0
of the recipe fixes this with a rolling per-node patch.

30-second invocation (Steps 3 – 5, assumes Step 0 done once already):

```bash
# Lower thresholds + for: durations
helm upgrade nkp-etcd-maintenance ./nkp-etcd-maintenance -n kube-system --reuse-values \
  --set alerts.thresholds.dbHighUsageRatio=0.01 \
  --set alerts.thresholds.dbCriticalUsageRatio=0.015 \
  --set alerts.thresholds.highFragmentationBytes=1048576 \
  --set alerts.for.memberNoLeader=30s \
  --set alerts.for.dbHighUsage=30s \
  --set alerts.for.dbCriticalUsage=30s \
  --set alerts.for.highFragmentation=30s

# Partition tcp/2380 on one follower (identify via etcdctl endpoint status --cluster)
FOLLOWER=<node-name-of-an-etcd-follower>
sed "s/REPLACE_ME_WITH_FOLLOWER_NODE/${FOLLOWER}/" docs/chaos/etcd-peer-partition.yaml | kubectl apply -f -
sleep 60   # alerts should be firing by now

# Cleanup
kubectl -n kube-system delete pod etcd-peer-partition
helm upgrade nkp-etcd-maintenance ./nkp-etcd-maintenance -n kube-system --reuse-values \
  --set alerts.thresholds.dbHighUsageRatio=0.7 \
  --set alerts.thresholds.dbCriticalUsageRatio=0.9 \
  --set alerts.thresholds.highFragmentationBytes=524288000 \
  --set alerts.for.memberNoLeader=1m \
  --set alerts.for.dbHighUsage=1h \
  --set alerts.for.dbCriticalUsage=5m \
  --set alerts.for.highFragmentation=1h
```

> **Safety:** Only partition a **follower**, never the leader. The recipe's
> Step 4a shows how to identify the leader via `etcdctl endpoint status
> --cluster`. The chaos Pod self-heals after 180 s; a `preStop` hook cleans
> the iptables rules on early delete.

---

## Quick Reference

| Goal | Command |
|---|---|
| Render chart YAML locally | `helm template nkp-etcd-maintenance ./nkp-etcd-maintenance` |
| Render with snapshot on | `helm template t ./nkp-etcd-maintenance --set snapshot.enabled=true` |
| Lint the chart | `helm lint ./nkp-etcd-maintenance` |
| Set kubeconfig | `export KUBECONFIG=~/nkp-test-kubeconfig.yaml` |
| Check cluster nodes | `kubectl get nodes` |
| Install / upgrade | `helm upgrade --install nkp-etcd-maintenance ./nkp-etcd-maintenance --namespace kube-system` |
| List Helm releases | `helm ls -n kube-system` |
| Check defrag CronJob | `kubectl get cronjob nkp-etcd-defrag -n kube-system` |
| Check snapshot CronJob | `kubectl get cronjob nkp-etcd-snapshot -n kube-system` |
| List all jobs | `kubectl get jobs -n kube-system` |
| Trigger manual defrag | `kubectl create job --from=cronjob/nkp-etcd-defrag manual-defrag-$(date +%s) -n kube-system` |
| Trigger manual snapshot | `kubectl create job --from=cronjob/nkp-etcd-snapshot manual-snapshot-$(date +%s) -n kube-system` |
| Create S3 creds Secret | `kubectl create secret generic etcd-backup-s3-creds -n kube-system --from-literal=access-key-id=<...> --from-literal=secret-access-key=<...>` |
| Capture latest job name | `JOB=$(kubectl get jobs -n kube-system --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}')` |
| Watch job pod | `kubectl get pods -n kube-system -l job-name=$JOB -w` |
| Follow defrag logs | `kubectl logs -n kube-system -l job-name=$JOB --follow` |
| Follow snapshot per-container logs | `kubectl logs <pod> -n kube-system -c take-snapshot` (and `-c verify-snapshot`, `-c upload`) |
| Inspect job details | `kubectl describe job -n kube-system $JOB` |
| Read all containers' logs (Events + WHY) | `kubectl logs job/$JOB -n kube-system --all-containers --prefix --tail=200` |
| Watch all Events in kube-system | `kubectl get events -n kube-system --sort-by=.lastTimestamp --watch` |
| Inspect the PrometheusRule | `kubectl get prometheusrule nkp-etcd-maintenance -n kube-system -o yaml` |
| List shipped alerts | `kubectl get prometheusrule nkp-etcd-maintenance -n kube-system -o yaml \| yq '.spec.groups[].rules[].alert'` |
| Disable a single alert | `helm upgrade nkp-etcd-maintenance ./nkp-etcd-maintenance --namespace kube-system --reuse-values --set alerts.rules.<AlertName>.enabled=false` |
| Disable all alerts | `helm upgrade nkp-etcd-maintenance ./nkp-etcd-maintenance --namespace kube-system --reuse-values --set alerts.enabled=false` |
| Silence an alert in Alertmanager (24 h) | `amtool silence add alertname=<AlertName> --duration=24h --comment="..."` |
| Helm release history | `helm history nkp-etcd-maintenance -n kube-system` |
| Roll back | `helm rollback nkp-etcd-maintenance 1 -n kube-system` |
| Uninstall | `helm uninstall nkp-etcd-maintenance --namespace kube-system` |
