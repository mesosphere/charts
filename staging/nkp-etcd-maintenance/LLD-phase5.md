# Low-Level Design — Phase 5: Snapshot MVP
## NKP etcd Maintenance Internship

**Jira:** NCN-114548
**Phase:** 5 — Snapshot MVP (was the "stretch" phase in the original brief;
promoted to a first-class deliverable for this iteration).
**Status:** Design only. This document is the gate that must be approved
before any chart code is written.
**Author:** intern, reviewed by senior MTS.

---

## 0. Executive Summary

Add a second CronJob to the existing `nkp-etcd-maintenance` chart that:

1. Takes a consistent etcd snapshot using the standard upstream tooling
   (`etcdctl snapshot save`).
2. Verifies the snapshot integrity (`etcdutl snapshot status`).
3. Uploads the verified snapshot to an S3-compatible object store using
   credentials supplied via a Kubernetes `Secret` (referenced — never
   embedded as plain text in values).
4. Documents in bold, repeated, hard-to-miss language that **restore is a
   manual operator procedure and is intentionally not automated by this
   addon**.

The design uses an **InitContainer + Main Container** pattern sharing an
`emptyDir` volume so we get strict ordering (capture → verify → upload),
use only upstream-published images (no custom build, no supply-chain risk),
and leave nothing behind on the node when the Job ends.

---

## 1. Outcome Criteria → Artefact Mapping

| Brief criterion | Artefact in Phase 5 |
|---|---|
| Scheduled snapshot using existing tooling | `templates/snapshot-cronjob.yaml` runs `etcdctl snapshot save` in an InitContainer using the upstream `registry.k8s.io/etcd` image |
| Verify snapshot using `etcdutl snapshot status` | Second command in the same InitContainer; non-zero exit fails the Job before any upload is attempted |
| Optional S3-compatible upload | Main container runs `minio/mc` (or `amazon/aws-cli`, switchable) to PUT the verified file. Skipped when `snapshot.s3.enabled: false` |
| `SecretRef` for credentials (no plain text) | `snapshot.s3.credentialsSecret.{name,accessKeyKey,secretKeyKey}` in values; the chart mounts them as env vars via `secretKeyRef`. No secret material in `values.yaml`, no secret material in the chart, no secret material in any Kommander override ConfigMap |
| Document manual restore | `README.md` §"Manual Restore Runbook" (new), this LLD §13–14, `COMMANDS.md` (Secret creation + restore reference) |

---

## 2. Goals & Non-Goals

### Goals
- Periodic, hands-off backup of etcd to an off-cluster object store.
- Snapshot integrity verified **before** upload (no silent corruption).
- Credentials supplied through a Kubernetes Secret the operator creates
  out-of-band.
- Same operational model as the existing defrag CronJob (kube-system,
  control-plane only, hostNetwork, hostPath PKI read-only).
- Zero additional container-image build pipeline. Use only upstream images.

### Non-Goals
- **Automated restore.** Out of scope. Documented as a manual operator
  procedure. See §13 for why.
- Snapshot lifecycle policy on the bucket (retention, GFS, glacier
  transitions). Defer to bucket-level lifecycle rules configured by the
  operator (S3 server-side feature, not an etcd concern).
- Cross-region replication of snapshots. Defer to bucket replication.
- Server-side encryption configuration beyond default-pass-through. The
  operator configures SSE on the bucket; the addon will respect what the
  bucket enforces but does not opt in/out per-upload.
- Encryption of the snapshot at rest before upload (client-side envelope
  encryption). Defer; users with this requirement should layer KMS in a
  follow-up phase.
- Snapshot deduplication, compression, or incremental backups. `etcdctl
  snapshot save` produces a single full file; that is the contract.
- Web UI for snapshot listing/management. Out of scope for a CronJob addon.

---

## 3. Why Add a CronJob (and Not Some Other Shape)

| Shape | Why we rejected it |
|---|---|
| **CronJob** (chosen) | Native to Kubernetes; declarative schedule; survives cluster upgrades; the operator already knows the shape; same pattern as the defrag CronJob; concurrency policy gives us "Forbid" out of the box. |
| Sidecar to the etcd static pod | Would require editing `kubeadm` static-pod manifests on every control-plane node. The brief explicitly forbids touching etcd lifecycle. Also yokes the snapshot lifecycle to the etcd pod lifecycle, which is wrong. |
| Standalone Deployment with internal scheduler (cron-in-pod) | Adds a long-running process with privileged mounts (`/etc/kubernetes/pki/etcd`) that never exits. The blast radius of a long-running privileged pod is much larger than that of a short-lived Job. We want to be on the node only during the snapshot window. |
| Dedicated operator (CRD + controller) | Massive overkill for a single periodic file write. Adds maintenance, RBAC, webhook surface. |
| External tool driven from outside the cluster (`etcdctl` from a jump host with TLS certs copied off-cluster) | Requires distributing the etcd CA & client cert off-cluster — a much worse security posture than keeping certs on the node and granting access only to a short-lived pod via read-only `hostPath`. |

**Decision: a `batch/v1` `CronJob` in `kube-system`, named `nkp-etcd-snapshot`.**

---

## 4. Architecture — The Two-Container Pattern

```
                ┌─────────────────────────────────────────────────────────┐
                │ Pod: nkp-etcd-snapshot-<datetime>-<hash>                 │
                │ nodeSelector: control-plane                              │
                │ hostNetwork: true        (to reach 127.0.0.1:2379)      │
                │                                                          │
                │  ┌────────────────────────────────────────────────────┐ │
                │  │ initContainer: snapshot                            │ │
                │  │   image: registry.k8s.io/etcd:<pinned tag>         │ │
                │  │   mounts: hostPath  /etc/kubernetes/pki/etcd  RO   │ │
                │  │           emptyDir  /snapshot                       │ │
                │  │                                                    │ │
                │  │   1. etcdctl snapshot save /snapshot/etcd.db       │ │
                │  │   2. etcdutl snapshot status /snapshot/etcd.db     │ │
                │  │                                                    │ │
                │  │   exit 0 only if BOTH succeed                      │ │
                │  └─────────────────────┬──────────────────────────────┘ │
                │                        │ Pod blocks; main container     │
                │                        │ does not start unless init     │
                │                        │ exits 0.                       │
                │  ┌─────────────────────▼──────────────────────────────┐ │
                │  │ container: upload                                  │ │
                │  │   image: minio/mc:<pinned tag>                     │ │
                │  │   env:  AWS_ACCESS_KEY_ID    ← secretKeyRef       │ │
                │  │         AWS_SECRET_ACCESS_KEY← secretKeyRef       │ │
                │  │   mounts: emptyDir  /snapshot  RO                  │ │
                │  │                                                    │ │
                │  │   mc alias set s3 <endpoint> $AKID $SAK            │ │
                │  │   mc cp /snapshot/etcd.db  s3/<bucket>/<key>       │ │
                │  └────────────────────────────────────────────────────┘ │
                │                                                          │
                │  emptyDir destroyed when Pod terminates → snapshot file │
                │  is ephemeral on the node. No on-host cleanup needed.   │
                └─────────────────────────────────────────────────────────┘
```

### 4.1 Why InitContainer → Main Container instead of two side-by-side containers

The Kubernetes runtime guarantees this ordering:

1. **All** init containers run to completion, in order, **before** any main
   container starts.
2. If any init container exits non-zero, the Pod's `restartPolicy` decides
   what happens. We use `restartPolicy: Never` (CronJob default) so a
   failed snapshot phase fails the entire Job immediately.

That contract gives us, for free:

- **"Verify before upload"** is enforced by the runtime, not by shell logic.
- **No partial uploads.** A corrupt or aborted snapshot never reaches S3
  because the upload container literally never starts.
- **Clear failure attribution.** Pod status reports which container failed
  → operator sees "init container `snapshot` failed" vs "container `upload`
  failed" without log-spelunking.

If we instead used **two side-by-side containers (sidecar pattern)**, both
would start concurrently and we'd need shell logic (a file flag, a fifo,
a sleep loop) to gate upload on snapshot completion. That logic is fragile
and we get nothing from it that the init-container ordering doesn't already
give us. Rejected.

If we instead used a **single container with both tools**, we'd need an
image that ships both `etcdctl`/`etcdutl` *and* `mc`/`aws`. That image
does not exist in any maintained registry. Building it ourselves means:

- A new CI pipeline.
- A new supply-chain attestation (SBOM, signatures, CVE scanning).
- Drift risk every time either upstream cuts a release.
- Adds a Nutanix-owned container image to the catalog (which the catalog
  already has plenty of and reviewers will push back on).

Rejected.

### 4.2 Why an emptyDir for the snapshot handoff

| Volume kind | Why we rejected (or accepted) it |
|---|---|
| **`emptyDir`** (chosen) | Pod-scoped, auto-deleted when Pod terminates, no node-side cleanup. Backed by node tmpfs/disk depending on cluster default — performance is fine for sequential writes of a single multi-GB file. No CSI required. Works on every cluster. |
| `hostPath: /var/lib/etcd-snapshots` | Leaves the snapshot file on the node after the Pod ends. We then need a separate cleanup mechanism, and a stray copy of the entire cluster state sitting on disk is a security liability (anyone with node-level read access has the whole cluster database, including Secrets, in clear text). Rejected. |
| `PersistentVolumeClaim` | Requires a CSI driver that can serve a volume to a control-plane node. Most CSI drivers (including Nutanix CSI) treat control-plane nodes as workload-free by default. Also adds a long-lived storage resource for what should be an ephemeral artifact. Rejected. |
| `tmpfs` `emptyDir.medium=Memory` | Same Pod-scoped guarantees as `emptyDir`, but counts against the Pod's memory limit. For a multi-GB etcd snapshot we don't want to compete with the kubelet/etcd for RAM on a control-plane node. Default disk-backed `emptyDir` is safer. |

**Decision: `emptyDir` (disk-backed, no `medium: Memory`), mounted as
read-write in the init container and read-only in the upload container.**
The read-only mount on the upload container is a defence-in-depth measure:
the uploader has no business modifying the snapshot it's uploading.

### 4.3 Sizing the emptyDir

By default `emptyDir` inherits the node's ephemeral storage capacity. We do
**not** set a `sizeLimit` because:

- etcd databases of ~6 GB are realistic on large clusters; setting an
  arbitrary `sizeLimit` would manufacture failures.
- We DO set an ephemeral-storage `requests.ephemeral-storage` on the Pod
  (configurable; default `2Gi`) so the scheduler accounts for the snapshot
  in its placement decision.

---

## 5. Image Choices — Explicit Comparison

### 5.1 Snapshot taker image

Requirements:
- Ships **both** `etcdctl` AND `etcdutl` (`etcdutl snapshot status` was
  split out of `etcdctl` in etcd 3.5+; we need both binaries).
- Maintained, signed, regularly published.
- Already pulled on most NKP control-plane nodes (so image-pull latency at
  02:30 UTC is near-zero).

| Candidate | etcdctl? | etcdutl? | Maintained? | Notes |
|---|:---:|:---:|---|---|
| **`registry.k8s.io/etcd`** (chosen) | yes | yes | yes — published by sig-etcd alongside each Kubernetes minor | Same image kubeadm pulls for the etcd static pod, so it is **already cached on every control-plane node**. Zero new supply-chain trust. |
| `quay.io/coreos/etcd` | yes | yes (3.5+) | maintained but slower release cadence than k8s.io | Adds an unrelated registry to the trust set. |
| `bitnami/etcd` | yes | yes | yes | Wraps an entrypoint that assumes server mode; would need `command: [/bin/sh, -c, etcdctl …]` to bypass. Works, but unnecessary friction. |
| `gcr.io/etcd-development/etcd` | yes | yes | deprecated mirror | Don't use. |
| Custom-built image | — | — | — | New CI + SBOM + sign + scan pipeline. Rejected. |

**Decision: `registry.k8s.io/etcd:<tag>`, default to `3.5.15-0`** (the tag
shipped with Kubernetes 1.30 / NKP 2.18). Operator can override
`snapshot.etcdImage.tag` to match their cluster's actual etcd minor — this
matters because mixing `etcdctl` of a much newer minor against an older
server may use unsupported RPCs.

The chart will provide a comment in `values.yaml` pointing the operator at
`kubectl exec -n kube-system etcd-<node> -- etcd --version` as the source
of truth for which tag to pin.

### 5.2 Uploader image

Requirements:
- Speaks the S3 wire protocol.
- Reads credentials from environment variables (so we can feed them via
  `valueFrom.secretKeyRef`).
- Works against non-AWS S3-compatible endpoints (MinIO, Ceph RGW, Nutanix
  Objects, NetApp StorageGRID, …).
- Small enough that pulling it at 02:30 UTC isn't a problem.

| Candidate | Size | Non-AWS endpoints | Notes |
|---|---|---|---|
| **`minio/mc`** (chosen default) | ~30 MB | first-class (`mc alias set --api S3v4 --path lookup`) | Single static Go binary. `--insecure` flag for self-signed S3 TLS in lab environments. Default. |
| `amazon/aws-cli:2` | ~200 MB | via `--endpoint-url` | Real AWS CLI; works fine with S3-compatible endpoints. Large image. |
| `rclone/rclone` | ~30 MB | yes (many backends) | Multi-backend complexity for a single use case. |
| Custom build with `s3cmd` / `awscli` slim | — | — | Same reasons as snapshot taker — don't build. |

**Decision: default `snapshot.uploader.image.repository = minio/mc`, tag
pinned, but the field is exposed in `values.yaml` so operators with a hard
"use AWS CLI" requirement can switch.** The container command shape is
different for `mc` vs `aws`, so switching uploader image also requires
swapping the `command` array — we'll handle this with a conditional in the
template (`{{- if eq .Values.snapshot.uploader.kind "mc" }}` etc.) and ship
both presets.

For the MVP we ship **only** the `mc` preset. The `aws` preset is documented
but commented-out in `values.yaml` to keep the surface area small. This is
the smallest thing that satisfies the brief.

---

## 6. Volume Model (complete)

| Volume name | Kind | Mounted on | Mode | Purpose |
|---|---|---|---|---|
| `etcd-pki` | `hostPath` | init container (`snapshot`) only | **readOnly: true** | Provides `ca.crt`, `server.crt`, `server.key` so `etcdctl` can authenticate to the local etcd. Identical pattern to the defrag CronJob — already validated in Phase 2. The upload container has **no need** for these certs and **must not** see them. |
| `snapshot-buffer` | `emptyDir` (disk-backed) | init container (`snapshot`): RW; main container (`upload`): **readOnly: true** | mixed | Carries the snapshot file between containers. Read-only on the uploader so a buggy uploader cannot tamper with the file post-verify. |

The upload container intentionally does **NOT** mount the PKI directory.
It only needs S3 credentials, which arrive as env vars from a Kubernetes
Secret. This is least-privilege by container.

---

## 7. Networking Model

- `hostNetwork: true` — same justification as the defrag CronJob: the etcd
  client listener is on `127.0.0.1:2379` on the host's net namespace; a
  pod-scoped loopback cannot reach it.
- The upload container also runs in `hostNetwork` (it has no choice — the
  Pod shares one netns). Egress to the S3 endpoint uses the node's normal
  routing. Operators with strict egress policies must allow the node's
  outbound traffic to the bucket endpoint.
- `dnsPolicy: ClusterFirstWithHostNet` so the upload container can still
  resolve cluster-internal names if the S3 endpoint is exposed via an
  in-cluster service (e.g., Nutanix Objects fronted by a Service). Without
  this, `hostNetwork` pods get only the node's resolver.

---

## 8. Security Model

### 8.1 SecretRef pattern — strict requirements

The brief says: "Use SecretRef for backup credentials rather than embedding
secrets in plain text." This is implemented at four layers:

| Layer | What we DO | What we EXPLICITLY DO NOT |
|---|---|---|
| `values.yaml` | Holds only **the Secret's name** and the **two key names** inside it. | Never contains actual credential material. |
| Helm template | Renders `valueFrom.secretKeyRef.{name,key}` into the container `env`. | Never renders the credential value itself. |
| Catalog defaults ConfigMap | Same as `values.yaml` — only the Secret reference. | Never contains credential material. |
| AppDeployment override ConfigMap (Kommander) | Same — only the Secret reference. | Never contains credential material. |

The operator creates the Secret out-of-band (documented in `COMMANDS.md`)
with:

```bash
kubectl create secret generic etcd-backup-s3-creds \
  --namespace kube-system \
  --from-literal=access-key-id='AKIAEXAMPLE' \
  --from-literal=secret-access-key='wJalrXUtnFEMI/K7MDENG/EXAMPLE'
```

And points the chart at it:

```yaml
snapshot:
  s3:
    credentialsSecret:
      name: etcd-backup-s3-creds
      accessKeyKey: access-key-id
      secretKeyKey: secret-access-key
```

#### Why `valueFrom.secretKeyRef` and not `envFrom.secretRef`

- `envFrom.secretRef` imports **every** key in the Secret as an env var.
  If the operator stores other unrelated material in the same Secret it
  leaks into the uploader's environment.
- `secretKeyRef` imports only the explicitly named keys → smallest blast
  radius. The user picks which two keys map to access/secret regardless of
  the Secret's internal naming convention.

#### Why env-vars and not files

- `mc` and `aws` CLIs both read S3 credentials from env vars by default.
- Mounting the Secret as a file would require us to either:
  (a) build an `~/.aws/credentials` file in an emptyDir (more moving parts), or
  (b) write a wrapper script (custom logic in the chart).
- Env-vars are the idiomatic path. The container's process tree is the
  blast radius, which is identical to the file case (both `procfs` and
  filesystem entries are visible to root inside the container).

### 8.2 Pod-level security

| Control | Setting | Why |
|---|---|---|
| `runAsUser` (init container) | `0` | `server.key` on the host is `0600 root:root`. Same justification as the defrag CronJob — `runAsNonRoot: false` does **not** force root; it merely disables the admission check. We need actual UID 0 to read the key. |
| `runAsUser` (upload container) | `0` | The `mc` image's default user is fine, but we set 0 to keep the two containers consistent and avoid surprises if a future image bump changes the default UID. The upload container has no host mounts so the UID doesn't have privileged-file consequences. |
| `allowPrivilegeEscalation` | `false` (both containers) | Defence in depth against setuid binaries inside the image. |
| `readOnlyRootFilesystem` | `true` (both containers) | Both tools write only to `/snapshot` (emptyDir, RW for init) and tmp (configurable). No reason to permit writes to `/`. |
| `capabilities.drop` | not set explicitly | Same reason as the defrag chart: dropping `DAC_OVERRIDE` would block the init container's read of `server.key` (0600 root:root, owned by root → still needs DAC_OVERRIDE? No — root bypasses DAC by default. But to be safe and consistent with the defrag pattern, we leave default caps in place). Reviewable. |

### 8.3 RBAC

The snapshot Job needs **no** Kubernetes API access. It does not list/get
pods, does not create events, does not touch the API server. It uses:

- The host filesystem (`hostPath`) to read certs.
- The host network (`hostNetwork`) to reach the etcd loopback.
- The S3 endpoint over the node's egress.

Therefore the ServiceAccount it runs as needs **no ClusterRole and no
RoleBindings**. We reuse the existing `nkp-etcd-maintenance-sa` (which
already exists for the defrag CronJob and has only `events: create/patch/update`)
to avoid proliferating SAs. The defrag SA's permissions are a strict
superset of what the snapshot job needs, so reusing it is sound.

### 8.4 Threat model — what an attacker who compromises the snapshot pod can do

| Capability | Mitigated by |
|---|---|
| Read etcd PKI material | Only the init container has the mount; the init container's process is `etcdctl` (sealed binary); `readOnlyRootFilesystem` prevents the attacker from dropping a backdoor binary. |
| Tamper with the snapshot before upload | `emptyDir` is mounted **readOnly** on the upload container. The attacker would have to compromise the running `etcdctl` process in the init container *and* the `mc` process in the upload container. |
| Exfiltrate the snapshot itself | The snapshot **is** uploaded to S3 by design — exfiltration of the snapshot is the addon's function. The defence here is auditing the S3 bucket access logs. |
| Use the snapshot pod as a pivot into etcd | The pod has the etcd client cert. Once the init container exits, the cert is no longer mounted into any running container (init mounts are dropped after init exits). The attacker would have to fully compromise the init container during its (<10 s) lifetime. |
| Use the S3 creds for off-target object actions | The credentials should be scoped at the bucket level by the operator (S3 bucket policy). Documented as an operator responsibility in §15. |

---

## 9. Scheduling Model

| Property | Value | Why |
|---|---|---|
| `schedule` | configurable, default `0 3 * * *` | Daily at 03:00 — 30 minutes after the defrag default (`30 2 * * *`) so the two jobs don't compete for control-plane CPU/disk. |
| `concurrencyPolicy` | `Forbid` | Two snapshot jobs running at once would race on the emptyDir and produce inconsistent uploads. |
| `restartPolicy` | `Never` | If snapshot or upload fails, surface the failure to the operator; the next scheduled tick is the retry mechanism. |
| `successfulJobsHistoryLimit` | `7` (configurable) | One week of job history visible for forensic queries. |
| `failedJobsHistoryLimit` | `7` (configurable) | One week of failed-job history so operators can investigate flapping. |
| `startingDeadlineSeconds` | `300` | If the controller is unavailable when the cron tick fires, skip after 5 minutes rather than spawning a stale Job hours later. |
| `ttlSecondsAfterFinished` | `86400` | Auto-clean Jobs (and their Pods) after 24 h. |

---

## 10. The values.yaml Schema (design — no code yet)

The chart's existing top-level keys (`defragmentation`, `image`,
`resources`, history limits) are unchanged. We add ONE new top-level key:
`snapshot:`. Full shape:

```yaml
snapshot:
  # Master toggle. Default false — snapshots require operator-supplied S3
  # configuration that we can't ship defaults for. Operator opts in.
  enabled: false

  # Cron schedule. UTC. Default = 30 min after the defrag schedule.
  schedule: "0 3 * * *"

  # Etcd connection — same shape as defragmentation.* for consistency.
  endpoint: "https://127.0.0.1:2379"
  etcdPkiHostPath: /etc/kubernetes/pki/etcd

  # Filename pattern. ${cluster}, ${ts}, ${node} are substituted at runtime
  # by a small shell template in the init container. ${ts} is UTC ISO-8601
  # without colons (`2026-06-09T03-00-15Z`) so it's filesystem-safe.
  # Default: <cluster>-<ts>.db
  objectKey: "${cluster}-${ts}.db"

  # The etcd container image that supplies etcdctl + etcdutl. See LLD §5.1.
  etcdImage:
    repository: registry.k8s.io/etcd
    tag: "3.5.15-0"
    pullPolicy: IfNotPresent

  # Resource ask for the snapshot init container. Snapshot is sequential
  # disk I/O — modest CPU; memory roughly tracks snapshot size's gzip
  # working set (etcdctl streams; ~256Mi covers multi-GB DBs).
  etcdResources:
    requests:
      cpu: 100m
      memory: 256Mi
      ephemeral-storage: 2Gi
    limits:
      cpu: 500m
      memory: 1Gi
      ephemeral-storage: 10Gi

  # ----------------------------------------------------------------
  # S3-compatible upload configuration. The 'upload' part is OPTIONAL:
  # if snapshot.s3.enabled is false the snapshot is taken & verified
  # but discarded (useful for debugging the snapshot path before wiring
  # storage). This is a deliberate decoupling.
  # ----------------------------------------------------------------
  s3:
    enabled: false

    # Endpoint URL. Examples:
    #   https://s3.amazonaws.com                      (AWS)
    #   https://minio.example.com                     (MinIO)
    #   https://objects.nutanix.example.com:443       (Nutanix Objects)
    endpoint: ""

    # Region. Required by most S3 implementations even when the endpoint
    # is non-AWS; "us-east-1" is the universally safe default.
    region: "us-east-1"

    # Bucket. Must already exist; the addon does not create buckets.
    bucket: ""

    # Optional prefix inside the bucket. Trailing slash is optional;
    # the chart normalises.
    prefix: "etcd-snapshots"

    # Path-style vs virtual-host-style addressing. Non-AWS endpoints
    # almost always require path-style (true). AWS supports both.
    pathStyle: true

    # If the S3 endpoint uses a self-signed cert (lab MinIO, test
    # Nutanix Objects deployments), set true. Default false (verify).
    insecureSkipTLSVerify: false

    # SecretRef. The chart NEVER receives the credential values; only
    # the references. The operator creates this Secret out-of-band.
    credentialsSecret:
      # Name of an existing Secret in the chart's release namespace.
      name: ""
      # Key inside the Secret holding the access key ID.
      accessKeyKey: "access-key-id"
      # Key inside the Secret holding the secret access key.
      secretKeyKey: "secret-access-key"

    # Upload tool. "mc" (MinIO Client, default) or "aws" (AWS CLI).
    uploader:
      kind: "mc"
      image:
        # mc default; if kind=aws, override to amazon/aws-cli.
        repository: minio/mc
        tag: RELEASE.2024-11-21T17-21-54Z
        pullPolicy: IfNotPresent

    # Resource ask for the uploader container — small (single PUT).
    resources:
      requests:
        cpu: 50m
        memory: 64Mi
      limits:
        cpu: 200m
        memory: 256Mi

  # CronJob history limits and concurrency.
  successfulJobsHistoryLimit: 7
  failedJobsHistoryLimit: 7
  startingDeadlineSeconds: 300
  ttlSecondsAfterFinished: 86400
```

**Invariants enforced at template-render time** (via Helm `fail` calls;
implementation detail, not in this design's scope but mentioned for
completeness):

- If `snapshot.enabled: true` AND `snapshot.s3.enabled: true`:
  - `snapshot.s3.endpoint` must be non-empty.
  - `snapshot.s3.bucket` must be non-empty.
  - `snapshot.s3.credentialsSecret.name` must be non-empty.

These fail the render with a human-readable message rather than producing
a CronJob that mysteriously crashes at 03:00 UTC.

---

## 11. The Snapshot Job — Detailed Container Specs (design)

This is the **shape** of the resources, not the YAML. The YAML lands in
Step 2 after your approval.

### 11.1 Init container `snapshot`

- **Image:** `{{ snapshot.etcdImage.repository }}:{{ tag }}`
- **Command:** `["/bin/sh", "-c", "<script>"]` where `<script>` is:

  ```sh
  set -eu
  TS=$(date -u +%Y-%m-%dT%H-%M-%SZ)
  CLUSTER="${CLUSTER_NAME:-etcd}"
  NODE="$(hostname)"
  OUT="/snapshot/${CLUSTER}-${TS}.db"

  # 1. Take the snapshot
  etcdctl \
    --endpoints="${ETCD_ENDPOINT}" \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    snapshot save "${OUT}"

  # 2. Verify integrity
  etcdutl snapshot status "${OUT}" -w table

  # 3. Hand the filename to the upload container by writing to a
  #    well-known location in the shared emptyDir.
  printf '%s\n' "${OUT}" > /snapshot/.path
  ```

- **Env (via Downward API + values):**
  - `CLUSTER_NAME` — from `.Values.snapshot.clusterName` or a fallback to
    chart release name.
  - `ETCD_ENDPOINT` — from `.Values.snapshot.endpoint`.
- **Mounts:**
  - `etcd-pki` (hostPath) → `/etc/kubernetes/pki/etcd` (readOnly)
  - `snapshot-buffer` (emptyDir) → `/snapshot` (read-write)
- **`securityContext`:** `runAsUser: 0, allowPrivilegeEscalation: false,
  readOnlyRootFilesystem: true`
- **Exit semantics:** any non-zero exit fails the Pod → no upload happens
  → CronJob marks the Job failed → operator alerted via standard tooling.

### 11.2 Main container `upload`

- **Image:** `{{ snapshot.s3.uploader.image.repository }}:{{ tag }}` —
  defaults to `minio/mc`.
- **Command (mc preset):**

  ```sh
  set -eu
  SRC="$(cat /snapshot/.path)"
  KEY="${PREFIX}/$(basename "${SRC}")"

  mc alias set target \
    "${S3_ENDPOINT}" \
    "${AWS_ACCESS_KEY_ID}" \
    "${AWS_SECRET_ACCESS_KEY}" \
    --api S3v4 \
    $( [ "${S3_PATH_STYLE}" = "true" ] && echo "--path" )

  mc cp \
    $( [ "${S3_INSECURE}" = "true" ] && echo "--insecure" ) \
    "${SRC}" "target/${S3_BUCKET}/${KEY}"
  ```

- **Env:**
  - `S3_ENDPOINT`, `S3_BUCKET`, `PREFIX`, `S3_PATH_STYLE`, `S3_INSECURE`
    from `.Values.snapshot.s3.*`.
  - `AWS_ACCESS_KEY_ID` from `secretKeyRef`
    (`{name: snapshot.s3.credentialsSecret.name, key: accessKeyKey}`).
  - `AWS_SECRET_ACCESS_KEY` from `secretKeyRef` (analogous).
- **Mounts:** `snapshot-buffer` (emptyDir) → `/snapshot` (**readOnly**)
- **`securityContext`:** `runAsUser: 0, allowPrivilegeEscalation: false,
  readOnlyRootFilesystem: true` — though note `mc` writes its alias config
  to `~/.mc/`; we'll set `HOME=/tmp/mc-home` and add a tmpfs `emptyDir`
  for `/tmp` to keep the root FS read-only. Detail for Step 2.
- **Exit semantics:** non-zero on upload failure surfaces to the Job and
  CronJob history.

### 11.3 When `snapshot.s3.enabled: false`

The upload container is omitted entirely (Helm conditional). The init
container still runs, takes the snapshot, verifies it, and the Pod
terminates as `Succeeded` after the (now empty) main container finishes.
We achieve "empty main container" by replacing it with a one-line
`busybox: ["/bin/true"]` container so the Job has something to schedule
and observability dashboards see green.

> **Open question for review:** alternative is to use `restartPolicy: OnFailure`
> with a single-container Pod that runs only the init steps when `s3.enabled:
> false`. Slightly cleaner; slightly more conditional Helm. Default to the
> two-container shape with a no-op upload for symmetry across the two modes.

---

## 12. Failure Modes & Idempotency

| Phase | Failure | Behaviour | Operator-visible signal |
|---|---|---|---|
| Snapshot save | etcd unreachable | `etcdctl` exits non-zero; init fails; upload never runs | CronJob Job status: Failed; init container logs visible |
| Snapshot save | Disk full (emptyDir) | `etcdctl` exits non-zero | Same |
| Snapshot status | Corrupt file (rare; would mean disk corruption mid-write) | `etcdutl` exits non-zero | Same — init logs show table or error |
| Upload | S3 endpoint unreachable | `mc cp` exits non-zero | CronJob Job status: Failed; main container logs visible |
| Upload | Wrong credentials | `mc cp` returns Access Denied | Same |
| Upload | Wrong bucket / no permission | `mc cp` returns NoSuchBucket / AccessDenied | Same |
| Upload | Network mid-transfer | `mc` retries internally (3 attempts); persistent failure exits non-zero | Same |

The CronJob's intrinsic retry mechanism is the next scheduled tick. We do
not add a `backoffLimit` on the Job (default is 6) — etcd snapshots are
quick, and immediate retries against the same (presumably broken) S3 are
not useful. We set `backoffLimit: 0` to fail fast and rely on the next
cron tick for retry. Operators with stricter RPO requirements can decrease
the cron schedule period or set `backoffLimit > 0`.

Idempotency: each run produces a uniquely-named object (`${cluster}-${ts}.db`)
in S3. Re-running does not overwrite a previous snapshot. Bucket lifecycle
policy is the operator's tool for old-snapshot deletion.

---

## 13. Restore Policy — Why It's Manual (and Why Automating It Would Be Wrong)

**The chart will never automate restore. This is a hard product decision.**

The reasoning, exhaustively:

1. **etcd is a Raft cluster, not a database file.**
   Restoring on one member while the other members continue to accept
   writes creates a split-brain. The cluster will silently diverge: the
   restored member will reject leader heartbeats it disagrees with, and
   the cluster's behaviour from that point is undefined. Doing this
   safely requires either:
   - **Single-node bootstrap:** stop etcd on all 3 members, wipe all 3
     data directories, restore on one member, restart it as a single-node
     cluster, add the other members back one at a time (which requires
     editing kubeadm static pod manifests on each).
   - **All-member synchronised restore:** stop etcd on all 3 members,
     restore the same snapshot to each (with different `--initial-cluster`
     values), restart them simultaneously.
   Both procedures require coordinated stops/starts across multiple
   nodes. A CronJob in one pod on one node cannot reliably coordinate
   that without acting as a full HA cluster operator — which is out of
   scope.

2. **The kubelet/kubeadm contract.**
   etcd on a kubeadm cluster is a **static pod** managed by the local
   kubelet from a manifest at
   `/etc/kubernetes/manifests/etcd.yaml`. To restore safely we must:
   - Move that manifest aside (kubelet stops the static pod within ~30 s).
   - Wipe `/var/lib/etcd/member`.
   - Place the restored data dir at `/var/lib/etcd/member`.
   - Move the manifest back (kubelet starts the static pod).
   An addon Pod cannot move static-pod manifests on the host without
   either a privileged hostPath write or a node-agent — both of which
   are large escalations of the addon's privilege model.

3. **API-server unavailability during restore.**
   While etcd is stopped, the Kubernetes API is down. Any addon
   coordinating restore can't talk to the API. We'd need an out-of-band
   coordination mechanism (rsync over SSH, ansible) which sits
   *outside* the cluster — which is exactly what a well-written restore
   runbook is.

4. **Reversibility asymmetry.**
   A wrongful backup is recoverable: delete the file. A wrongful
   restore is not recoverable: it overwrites the live cluster state. The
   blast radius of an automated restore bug is the entire cluster.

5. **Compliance.**
   Many enterprise change-control processes require a human approval
   gate for any operation that wipes the cluster datastore. An automated
   restore would bypass this control by design.

6. **The brief.**
   The internship brief lists restore as out of scope. We honour the
   contract.

The chart therefore ships the snapshot upload but **deliberately ships no
restore mechanism**. The README will carry a runbook explaining the
manual procedure, with the explicit warning that the operator owns the
outcome.

---

## 14. Manual Restore Runbook — Outline (lands in README in Step 4)

The Step 4 README addition will be a single, prominent, top-of-page-linked
section. Outline:

1. **"Stop. Read this first."** Warning callout describing data loss
   scenarios.
2. **Pre-conditions checklist.** Snapshot file already downloaded from S3
   to a jump host with SSH to all control-plane nodes. Maintenance window
   declared. Application traffic understood (workloads will tolerate
   `apiserver` unavailability or be drained).
3. **Procedure (single-CP recovery from disaster).** etcd is dead, must
   bring back from snapshot:
   - Copy snapshot to the CP node.
   - `etcdutl snapshot restore` to produce a new data dir.
   - Move the kubeadm static manifest aside; wipe `/var/lib/etcd`; move
     restored data dir into place; restore manifest.
   - Validate API server comes back; `kubectl get nodes` returns sane data.
4. **Procedure (multi-CP).** Reset & rejoin each additional member using
   `kubeadm join` after the bootstrap node is healthy.
5. **Validation checks.** `etcdctl endpoint status -w table`,
   `kubectl get componentstatuses` (legacy), `kubectl get nodes` consistent
   with what was running.
6. **Post-restore hygiene.** Rotate workload secrets if the snapshot age
   suggests credentials in it may be stale. Re-enable the snapshot CronJob.
7. **Sign-off.** Operator records the time, the snapshot file used, and
   the validation commands' output in their incident log.

---

## 15. Operator Responsibilities (documented; not enforced by chart)

- **Bucket policy.** Scope the IAM/S3 user to `s3:PutObject,GetObject,ListBucket`
  on the specific `${bucket}/${prefix}/*` path only. Do not use a root key.
- **Bucket retention.** Set a lifecycle rule on the bucket to delete old
  snapshots per the organisation's RPO/RTO policy. The chart does not
  delete objects.
- **Bucket encryption.** Enable SSE-S3 or SSE-KMS on the bucket. Snapshot
  content is the entire cluster state including Secrets — encrypt at rest.
- **Network egress.** If the cluster is in a private subnet, ensure the
  control-plane nodes have egress to the S3 endpoint (NAT, VPC endpoint,
  or in-cluster Service).
- **Secret rotation.** Rotate the S3 access key periodically. Updating the
  Kubernetes Secret is sufficient — the next CronJob run picks up the new
  value because env-from-secretKeyRef is resolved at pod creation.
- **Monitor CronJob status.** Add a Prometheus rule on
  `kube_job_failed{job_name=~"nkp-etcd-snapshot.*"}` or equivalent and
  alert on consecutive failures.

These are listed in `README.md` Step 4 and again on the catalog
`metadata.yaml` "overview" pane so they're impossible to miss.

---

## 16. Acceptance Criteria (gates Phase 5 done)

A. **Functional**
   1. `helm install` with `snapshot.enabled=true, snapshot.s3.enabled=true`
      and a valid Secret produces an object in the bucket within one cron
      tick.
   2. The object opens cleanly with `etcdutl snapshot status` on a fresh
      machine (proof of valid full snapshot, not just a truncated PUT).
   3. With `snapshot.s3.enabled=false`, the Job runs to success without
      contacting any external endpoint; logs show the snapshot was taken
      and verified.
   4. With a wrong Secret name in values, the chart `helm template` step
      fails with a clear message (no silent breakage at 03:00 UTC).
   5. The defrag CronJob is unaffected — Phase 2's validation continues to
      hold.

B. **Security**
   1. `helm template … --debug` output contains zero credential material.
   2. `kubectl get cronjob nkp-etcd-snapshot -o yaml` shows
      `valueFrom.secretKeyRef`, not literal values.
   3. The init container's PKI hostPath mount is `readOnly: true`.
   4. The upload container does not mount the PKI hostPath.
   5. The upload container's snapshot mount is `readOnly: true`.

C. **Documentation**
   1. README has a "Manual Restore Runbook" section linked from the TOC
      and from the top-of-file warning band.
   2. `COMMANDS.md` includes the `kubectl create secret` recipe and the
      `etcdutl snapshot restore` reference.
   3. `metadata.yaml` (Kommander catalog) mentions snapshot configuration
      in the overview pane.

D. **Compatibility**
   1. Chart `helm lint` clean.
   2. Catalog repo's `nkp validate catalog-repository` passes with the
      new defaults ConfigMap entries.
   3. Existing defrag-only operators are not forced to set any new value:
      `snapshot.enabled` defaults to `false`.

---

## 17. Open Questions / Decisions Deferred to Step 2

These do not block design approval but will be made concrete in Step 2.

1. Whether to expose `snapshot.objectKey` template (cluster/ts/node
   placeholders) as user-overridable in Phase 5 MVP or hard-code the
   pattern. Lean: hard-code in MVP, expose in 5.1.
2. Whether to add a Prometheus `ServiceMonitor` for the snapshot Job's
   `kube_job_status_failed` counter. Lean: out of scope for MVP — operators
   already monitor CronJob failures with their generic K8s alerting.
3. Whether to support encrypting the snapshot file before upload with
   a KMS envelope. Lean: defer to Phase 5.2 — keep MVP small.
4. Whether to also support `snapshot.s3.uploader.kind: "aws"` in MVP or
   only `mc`. Lean: ship only `mc` in MVP, document `aws` as a 5.1 add.

---

## 18. Step 2 Preview (will execute only after this LLD is approved)

When you approve this design I will, in order:

1. Add the entire `snapshot:` block from §10 to `values.yaml` with the
   same comment style as the existing `defragmentation:` block.
2. Create `templates/snapshot-cronjob.yaml` matching §11.
   - Will be guarded top-to-bottom by `{{- if .Values.snapshot.enabled -}}`.
   - Will include a Helm `fail` for the invariants in §10.
   - Will reuse the existing `nkp-etcd-maintenance-sa` ServiceAccount
     (no new RBAC).
3. Run `helm lint` and `helm template` locally to confirm both the
   defrag-only and snapshot-enabled renders are valid.
4. Pause for review again before Step 3 (catalog `cm.yaml` update).

**No code is being written until you approve this LLD.** Reply with
"approved" or with specific changes you want before I proceed.
