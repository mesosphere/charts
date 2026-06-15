# LLD — Phase Observability (Alerts, Events, Logs, Documentation)

> **Status:** Draft v1, awaiting user approval. No chart or doc changes have been written yet. This document follows the same structure as `LLD-phase5.md`.

---

## 0. Summary in three lines

This phase makes the `nkp-etcd-maintenance` addon **observable** by an external Prometheus stack and **legible** to a human operator. It adds a `PrometheusRule` covering four classes of failure (unhealthy etcd, defrag failure, snapshot failure, high fragmentation) and finishes the user-facing documentation surface that the addon ships with. No new container images, no new RBAC, no behavioural change to the existing CronJobs.

---

## 1. Goals (mapped to outcome criteria)

| # | Outcome criterion | Deliverable | Where it lands |
|---|---|---|---|
| 1 | Generate Kubernetes Events for successful and failed maintenance runs. | Use **native** Job/CronJob controller Events; no custom emission. | Existing CronJob templates; no edits. Documentation in README/COMMANDS. |
| 2 | Implement clear job logs. | Structured `[phase] event=value` prefixes in the snapshot upload script. ahrtr/etcd-defrag's own output kept as-is. | Minor edit to `templates/snapshot-cronjob.yaml` upload script. |
| 3 | PrometheusRule alerts: unhealthy etcd, defrag fails, snapshot fails, high fragmentation. | New `templates/prometheusrule.yaml` + `alerts.*` values block. Eight alerts. | New file + values addition. |
| 4 | Doc: what the addon does, enable/disable, default schedules. | Rewritten "About" + "Quick start" + "Toggles" sections in README. | README. |
| 5 | Doc: inspect jobs, read failures. | New "Inspect & diagnose" section in COMMANDS.md with the exact kubectl commands and expected output shapes. | COMMANDS.md. |
| 6 | Doc: manual restore caveat. | Already shipped in Phase 5 (`README.md#manual-restore-runbook`). Cross-link from new sections + add a "Caveats" callout to the addon overview. | README. |
| 7 | Doc: project limitations and non-goals. | Dedicated `## Limitations` and `## Non-goals` sections in README. | README. |

---

## 2. Non-goals (explicit)

| # | Non-goal | Why |
|---|---|---|
| NG-1 | Ship a Prometheus instance or Prometheus Operator. | We are a maintenance addon. The cluster's observability stack (Kommander's `kube-prometheus-stack` platform-app or equivalent) provides Prometheus. |
| NG-2 | Reimplement the upstream etcd Prometheus mixin (gRPC latencies, fsync durations, proposal failures, leader-change rates, etc.). | Out of scope of the four outcome criteria. The mixin is ~15 alerts; we add only those that target our maintenance behaviour. Operators wanting deeper etcd telemetry should install the mixin separately. |
| NG-3 | Emit custom Kubernetes Events from inside the maintenance containers. | Adds kubectl-in-container or curl + service-account-token plumbing for marginal info gain. Native controller Events already cover success/fail. Container logs cover the "why". |
| NG-4 | Alert on defrag *being skipped* (rule didn't fire). | A skipped defrag is the CORRECT behaviour when the rule doesn't match; alerting on it would be noise. We alert on missing **runs**, not skipped operations. |
| NG-5 | Auto-remediate from alerts. | Defrag fires on cron; snapshot fires on cron; we don't take alert-driven actions. Operators decide. |
| NG-6 | Manage S3 retention via Prometheus alert callbacks. | Retention is a bucket-lifecycle concern, not an alerting concern. |
| NG-7 | Cover etcd topologies other than kubeadm-managed (static-pod etcd with `/etc/kubernetes/pki/etcd` on the node). | Out of scope of the chart entirely (also documented in §13 Limitations and in the existing preflight job). |

---

## 3. Architecture overview

```
                              ┌─────────────────────────────────────────┐
                              │  Prometheus Operator stack               │
                              │  (kube-prometheus-stack or equivalent)   │
                              │                                          │
                              │  Watches:                                │
                              │   - PrometheusRule CRs (this PR)         │
                              │   - kube-state-metrics for K8s objects   │
                              │   - etcd /metrics for db & cluster state │
                              │                                          │
                              │           ┌──────────────────┐           │
                              │           │ Alertmanager     │           │
                              │           └────────┬─────────┘           │
                              └───────────────────││────────────────────┘
                                                  ││
                                  ┌───────────────┘└────────────┐
                                  ▼                             ▼
                             on-call paging                 dashboards/UI
                             (Slack/PagerDuty)              (Grafana)

────────────────────────────── what this chart ships ──────────────────────────────

  templates/prometheusrule.yaml          ← NEW (this phase)
    apiVersion: monitoring.coreos.com/v1
    kind: PrometheusRule
    gated on:
      .Values.alerts.enabled  AND
      .Capabilities.APIVersions.Has "monitoring.coreos.com/v1/PrometheusRule"

    groups:
      - name: nkp-etcd-maintenance.etcd-health
          rules: EtcdMemberNoLeader, EtcdDbHighUsage, EtcdDbCriticalUsage,
                 EtcdHighFragmentation
      - name: nkp-etcd-maintenance.defrag
          rules: EtcdDefragJobFailed, EtcdDefragJobMissed
      - name: nkp-etcd-maintenance.snapshot  (only if .Values.snapshot.enabled)
          rules: EtcdSnapshotJobFailed, EtcdSnapshotJobMissed

  templates/defrag-cronjob.yaml           ← UNCHANGED
  templates/snapshot-cronjob.yaml         ← minor: tighter [upload] log prefixes
  templates/rbac.yaml                     ← UNCHANGED
                                            (events RBAC already granted in
                                             Phase 2; no new permissions)
```

### How the three outcome streams compose

```
EVENT STREAM  (kubectl describe / kubectl events)
  source: native Job + CronJob controller
  audience: operator who knows there's a problem and wants the why
  examples:
    - CronJob 'nkp-etcd-snapshot' scheduled job 'nkp-etcd-snapshot-1780310595'
    - Job 'nkp-etcd-defrag-1780310595' has reached the specified backoff limit
    - Pod 'nkp-etcd-snapshot-1780310595-xj4kw' init container take-snapshot exited with 1

LOG STREAM    (kubectl logs)
  source: container stdout/stderr
  audience: operator debugging a specific run
  examples:
    [take-snapshot]   etcdctl JSON: msg=saved path=/snapshot/etcd.db
    [verify-snapshot] etcdutl table: hash=abc123 revision=168972 size=76 MB
    [upload] phase=start target=nkp-etcd-backups/etcd-snapshots/<cluster>-<ts>.db
    [upload] phase=alias-set endpoint=https://minio.example.com path-style=on
    [upload] phase=copy bytes=80000000
    [upload] phase=success duration=12s

ALERT STREAM  (Prometheus → Alertmanager → on-call)
  source: PrometheusRule (this chart) evaluated against etcd + KSM metrics
  audience: people NOT looking at the cluster, who need to be told something is wrong
  examples:
    [WARN]  EtcdDefragJobFailed: 1 defrag Job in kube-system is in Failed state
    [CRIT]  EtcdSnapshotJobMissed: nkp-etcd-snapshot has not scheduled in 2d 4h
    [CRIT]  EtcdDbCriticalUsage: etcd db at 92% of quota on member 10.22.202.156
```

The three streams are **independent and complementary**. An operator can answer "is something broken?" with one (alerts), "what's broken?" with another (events), and "why is it broken?" with the third (logs).

---

## 4. Component 1 — Native Kubernetes Events

### 4.1 What the controllers emit for free

The Job and CronJob controllers already emit the Events we need. We do nothing in the chart; the events appear automatically.

| Event source | Reason | Example message | When |
|---|---|---|---|
| CronJob controller | `SuccessfulCreate` | Created job `nkp-etcd-defrag-1780310595` | Every successful scheduling |
| CronJob controller | `SawCompletedJob` | Saw completed job `nkp-etcd-defrag-1780310595, condition: Complete` | After a Job completes |
| CronJob controller | `MissingJob` | Active job went missing: `nkp-etcd-defrag-1780310595` | Job manifest GC'd before controller saw completion |
| Job controller | `SuccessfulCreate` | Created pod: `nkp-etcd-defrag-1780310595-abcde` | Per-pod scheduling |
| Job controller | `BackoffLimitExceeded` | Job has reached the specified backoff limit | Failure (our `backoffLimit: 0` makes this fire on first pod failure) |
| Kubelet (per-pod) | `Failed`, `BackOff` | Back-off restarting failed container | Pod-level failures, image-pull issues, OOMKills |

### 4.2 Why we do NOT add custom Event emission

| Option | Verdict | Reason |
|---|---|---|
| `kubectl create event` inside the container | Rejected | Requires kubectl binary in the container. mc image (minio/mc) is alpine; we'd need to install kubectl into the image or build a custom one. New supply-chain surface. |
| Direct K8s API call via curl + SA token | Rejected | Requires SA token mounted, curl binary, JSON crafting. Increases image surface and template complexity for ~4 extra Events per run that duplicate the controller's. |
| The Eventing-API client (Go) baked into a custom binary | Rejected | Means we ship a binary. The whole point of the design in Phase 5 §5 was to NOT ship a custom image. |
| **Native controller Events only** | **Accepted** | Free, idiomatic, already covers the success/fail classification the outcome criterion asks for. Detail beyond pass/fail belongs in logs. |

### 4.3 Reserved future work

The existing ClusterRole grants `events: create,patch,update` (added in Phase 2 for the defrag SA). We keep that grant so a future phase can opt into application-specific Events (e.g. an "etcd-defrag-skipped: rule did not match" event) without an RBAC change.

---

## 5. Component 2 — Clear job logs

### 5.1 Outputs we don't control

| Component | Log source | Format | Action |
|---|---|---|---|
| `nkp-etcd-defrag` (only container) | `ghcr.io/ahrtr/etcd-defrag` binary stdout | Timestamped human-readable lines (`10:43:22 Defragmenting https://...`) | Accept as-is. The output is clear, sortable, and grep-friendly. Documented in COMMANDS §8.5-equivalent. |
| `take-snapshot` (init) | `etcdctl` JSON logger | One JSON object per line (`{"level":"info","msg":"saved",...}`) | Accept. Pipe-able into jq. Documented. |
| `verify-snapshot` (init) | `etcdutl snapshot status -w table` | Single ASCII table | Accept. Operator sees hash, revision, total-keys, total-size at a glance. |

### 5.2 Output we DO control: the upload container's shell script

Current state (after Phase 5):

```
[upload] target: nkp-etcd-backups/etcd-snapshots/<cluster>-<ts>.db
[upload] endpoint: https://minio.example.com (path-style=on)
... (mc output) ...
[upload] success: nkp-etcd-backups/etcd-snapshots/<cluster>-<ts>.db
```

This is already reasonable. The Phase Observability change is to **tighten it to a single, structured `[phase] key=value` shape** so log-shipping (Loki, Splunk, FluentBit grok patterns) parses it without per-line custom rules. Proposed format:

```
[upload] phase=start ts=<UTC-ISO8601> target_bucket=<bucket> target_key=<key>
[upload] phase=alias-set endpoint=<url> path-style=on|off api=S3v4
[upload] phase=copy source=/snapshot/etcd.db
... (mc cp progress lines, unchanged) ...
[upload] phase=success bytes_uploaded=<n> wall_clock_seconds=<n>
```

On failure:
```
[upload] phase=alias-set-failed exit_code=<n>
```
or
```
[upload] phase=copy-failed exit_code=<n>
```

Why structured `key=value` and not free text:
- Grep-friendly: `kubectl logs ... -c upload | grep 'phase=success'` is a one-line health check.
- Trivially parseable in any log shipper without custom regex.
- Mirrors the convention many production tools use (e.g., logfmt).

### 5.3 What we do NOT change

- The defrag CronJob's container has only the binary's output; not reformatting.
- The init containers run the etcd image binaries directly with no shell wrapping; not reformatting.
- No JSON wrapping. logfmt-style remains readable on a console without `jq`.

---

## 6. Component 3 — PrometheusRule (the deep dive)

### 6.1 Why a `PrometheusRule` and not a ConfigMap of alerts

| Option | Verdict | Reason |
|---|---|---|
| ConfigMap with rules in `data`, mounted into a manually-configured Prometheus | Rejected | Couples this chart to a specific Prometheus deployment topology. The Operator pattern is the platform-wide standard. |
| `PrometheusRule` CR (`monitoring.coreos.com/v1`) | **Accepted** | Auto-discovered by the Prometheus Operator via label selectors. Same pattern as `ndk`, `kserve`, every other Kommander platform app. |
| Sidecar in Prometheus that reloads files | Rejected | Same problem as the ConfigMap option but worse — requires running Prometheus with a specific sidecar. |

### 6.2 Discovery contract

The Prometheus Operator's `Prometheus` CR has a `ruleSelector` like:
```yaml
ruleSelector:
  matchLabels:
    release: kube-prometheus-stack
```

Different bundles use different label values. We expose this via `alerts.additionalLabels` so an operator who installed Prometheus with the `prometheus` label name set to `monitoring` (or anything else) can match.

Default value (matches kube-prometheus-stack's vanilla install):
```yaml
alerts:
  additionalLabels:
    release: kube-prometheus-stack
```

### 6.3 Capability-gated rendering

```yaml
{{- if and .Values.alerts.enabled (.Capabilities.APIVersions.Has "monitoring.coreos.com/v1/PrometheusRule") -}}
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  ...
{{- end }}
```

**Behaviour matrix**:

| `alerts.enabled` | CRD installed | Resource rendered? | Result |
|---|---|---|---|
| `false` | irrelevant | No | Operators on bare clusters opt out. |
| `true` | yes | Yes | Default: rule installs, Prometheus picks it up. |
| `true` | **no** | **No** (silent) | Helm install does NOT fail. Operator can install kube-prometheus-stack later then `helm upgrade` to materialise the rule. |

The third row is critical: it means `alerts.enabled: true` (our default) is safe even on a fresh cluster that has not yet installed the observability stack. The chart never crashes the install.

---

## 7. PromQL alert catalog

Eight alerts, organised into three groups (the third is gated by `snapshot.enabled`).

Conventions used below:
- All queries scope `namespace="kube-system"` because that's where both CronJobs live (defrag CronJob is in `kube-system`; snapshot CronJob is in `kube-system`; etcd is in `kube-system` as a static pod).
- Thresholds and `for:` durations are values-configurable; the table shows defaults.
- Each alert carries `labels.severity`, `labels.component`, `annotations.summary`, `annotations.description`, `annotations.runbook_url`.

### Group A — `nkp-etcd-maintenance.etcd-health` (always rendered)

#### A1 — `EtcdMemberNoLeader`

| Field | Value |
|---|---|
| Severity (default) | `critical` |
| `for` (default) | `1m` |
| Query | `etcd_server_has_leader{job="kube-etcd"} == 0` |
| Why this metric | `etcd_server_has_leader` is `1` when a member has a leader, `0` otherwise. Emitted by etcd itself, scraped by Prometheus via the standard `kube-etcd` ServiceMonitor. |
| Why `for: 1m` | Brief leader-loss during normal leader election (e.g., after a defrag-and-leader-transfer step) recovers within seconds. 1m avoids paging on benign elections; anything past 1m is a real outage. |
| Annotation `summary` | `Etcd member has no leader for >1m` |
| Annotation `description` | `Etcd member {{ $labels.instance }} reports no leader for {{ $for }}. Quorum may be lost.` |

#### A2 — `EtcdDbHighUsage`

| Field | Value |
|---|---|
| Severity | `warning` |
| `for` | `1h` |
| Query | `(etcd_mvcc_db_total_size_in_bytes / etcd_server_quota_backend_bytes) > 0.7` |
| Why | Approaching the quota means a NOSPACE alarm is the next failure mode. The defrag CronJob reduces `etcd_mvcc_db_total_size_in_bytes` directly; if usage stays above 70 % the defrag is either disabled, failing, or under-tuned. |
| Why `1h` | The defrag runs at most once a day, so a 1-hour sustained breach genuinely means the rule didn't help. |
| Summary | `Etcd database is >70% of its quota on {{ $labels.instance }}` |
| Description | Includes the actual ratio: `{{ $value \| humanizePercentage }}` |

#### A3 — `EtcdDbCriticalUsage`

| Field | Value |
|---|---|
| Severity | `critical` |
| `for` | `5m` |
| Query | `(etcd_mvcc_db_total_size_in_bytes / etcd_server_quota_backend_bytes) > 0.9` |
| Why | At 90 % the cluster is one bad write storm from NOSPACE. Page on-call. |
| Why `5m` | Sustained — not a brief spike from a one-time write burst. |

#### A4 — `EtcdHighFragmentation`

| Field | Value |
|---|---|
| Severity | `warning` |
| `for` | `1h` |
| Query | `(etcd_mvcc_db_total_size_in_bytes - etcd_mvcc_db_total_size_in_use_in_bytes) > 524288000` (500 MiB default, configurable) |
| Why these metrics | Direct analogue of the default defrag rule (`dbSize - dbSizeInUse > 200 MiB`). When fragmentation stays high for 1h the daily defrag either didn't run or didn't help. |
| Why 500 MiB and not the rule's 200 MiB | The defrag rule is the **trigger** for action; the alert is the **escalation** when action didn't help. Setting the alert threshold higher than the rule (500 vs 200) avoids alerting in the normal accumulate-then-defrag cycle. |
| Caveat documented in annotation | "Fragmentation alone is benign; this alert means defrag should have reduced it but didn't." |

### Group B — `nkp-etcd-maintenance.defrag` (always rendered)

#### B1 — `EtcdDefragJobFailed`

| Field | Value |
|---|---|
| Severity | `warning` |
| `for` | `5m` |
| Query | `sum by (namespace, job_name) (kube_job_status_failed{namespace="kube-system", job_name=~"nkp-etcd-defrag-.*"}) > 0` |
| Why this metric | `kube_job_status_failed` is emitted by kube-state-metrics for every Job, counting failed pods. With our `backoffLimit: 0` (set in Phase 2), any failed pod ⇒ Job in Failed state ⇒ this metric > 0. |
| Why warning, not critical | A single missed defrag is recoverable. Defrag is rule-gated, so a one-day skip is usually a no-op anyway. Operators should investigate but not be paged at 3am. |
| Caveat | `kube_job_status_failed > 0` persists until the CronJob's `failedJobsHistoryLimit` GCs the failed Job (3 by default). The alert thus fires for "the last failed defrag still on record", which is actually the desired behaviour — operators want to know the most recent run failed. |
| Alt query (time-windowed, in template comment for ops who want it) | `kube_job_failed{...} == 1 unless on(namespace, job_name) (time() - kube_job_status_start_time{...}) > 3600` |

#### B2 — `EtcdDefragJobMissed`

| Field | Value |
|---|---|
| Severity | `warning` |
| `for` | `30m` |
| Query | `time() - kube_cronjob_status_last_schedule_time{namespace="kube-system", cronjob="nkp-etcd-defrag"} > 86400 * 2` |
| Why | Pure failure-counting misses the case where the CronJob never fires — suspended (`suspend: true`), missing PV / volume, deleted by accident, controller crash-loop. `last_schedule_time` is the canonical "did this CronJob actually emit a Job?" signal. |
| Why `2 days` | Default defrag schedule is daily; allowing 2 days catches a missed tick without false-positiving on a one-time skip due to `concurrencyPolicy: Forbid`. Configurable. |

### Group C — `nkp-etcd-maintenance.snapshot` (only rendered when `.Values.snapshot.enabled`)

#### C1 — `EtcdSnapshotJobFailed`

| Field | Value |
|---|---|
| Severity | **`critical`** (intentionally higher than defrag) |
| `for` | `5m` |
| Query | `sum by (namespace, job_name) (kube_job_status_failed{namespace="kube-system", job_name=~"nkp-etcd-snapshot-.*"}) > 0` |
| Why critical | Defrag failures degrade performance; snapshot failures degrade *recoverability*. If a disaster strikes between failed snapshot and remediation, data is lost. Page on-call. |

#### C2 — `EtcdSnapshotJobMissed`

| Field | Value |
|---|---|
| Severity | `critical` |
| `for` | `30m` |
| Query | `time() - kube_cronjob_status_last_schedule_time{namespace="kube-system", cronjob="nkp-etcd-snapshot"} > 86400 * 2` |
| Why | Same as B2; criticality matches C1's rationale. |

### 7.10 Why we do NOT alert on these (explicit non-alerts)

| Did not alert | Reason |
|---|---|
| Defrag skipped because rule didn't match | This is the *correct* behaviour. Alerting would be noise. |
| Snapshot verified-but-not-uploaded (S3 off mode) | Operator's deliberate config choice (`snapshot.s3.enabled: false`). |
| `etcd_server_leader_changes_seen_total` high rate | Belongs in the upstream etcd mixin; out of our scope. Operators wanting it should install the mixin. |
| Container OOMKill | Surfaced via `KubePodCrashLooping` from the standard kube-prometheus-stack alert set; duplicating it here would be redundant. |

---

## 8. values.yaml schema

```yaml
# ------------------------------------------------------------------
# PrometheusRule (Phase Observability)
# ------------------------------------------------------------------
alerts:
  # -- Master toggle. Default true. Even when true, the rule is only
  # rendered if the Prometheus Operator CRD (monitoring.coreos.com/v1
  # PrometheusRule) is present on the cluster, so installing on a
  # cluster without an observability stack is safe.
  enabled: true

  # -- Labels added to the PrometheusRule resource metadata so the
  # Prometheus Operator's `ruleSelector` picks it up. Default value
  # matches a vanilla kube-prometheus-stack install. Override if your
  # cluster's Prometheus uses a different `ruleSelector`.
  additionalLabels:
    release: kube-prometheus-stack

  # -- Default labels applied to every alert. Useful for routing
  # (e.g., team: platform → goes to platform-on-call).
  defaultLabels: {}

  # -- Default annotations applied to every alert.
  defaultAnnotations: {}

  # -- Base URL for runbook_url annotations. Each alert appends its
  # anchor (e.g., #etcdmembernoleader) to produce the final URL.
  runbookBaseUrl: "https://github.com/nutanix-cloud-native/nkp-etcd-maintenance/blob/main/README.md"

  # -- Per-alert thresholds. All exposed; defaults match §7.
  thresholds:
    dbHighUsageRatio: 0.7
    dbCriticalUsageRatio: 0.9
    highFragmentationBytes: 524288000   # 500 MiB
    missedScheduleSeconds: 172800       # 2 days

  # -- Per-alert `for:` durations.
  for:
    memberNoLeader: 1m
    dbHighUsage: 1h
    dbCriticalUsage: 5m
    highFragmentation: 1h
    defragJobFailed: 5m
    defragJobMissed: 30m
    snapshotJobFailed: 5m
    snapshotJobMissed: 30m

  # -- Per-alert enable/severity. Operators with their own
  # etcd-health alerts can disable the four "etcd-health" alerts and
  # keep only the CronJob failure ones (or vice versa).
  rules:
    EtcdMemberNoLeader:    { enabled: true, severity: critical }
    EtcdDbHighUsage:       { enabled: true, severity: warning  }
    EtcdDbCriticalUsage:   { enabled: true, severity: critical }
    EtcdHighFragmentation: { enabled: true, severity: warning  }
    EtcdDefragJobFailed:   { enabled: true, severity: warning  }
    EtcdDefragJobMissed:   { enabled: true, severity: warning  }
    EtcdSnapshotJobFailed: { enabled: true, severity: critical }
    EtcdSnapshotJobMissed: { enabled: true, severity: critical }

  # -- Scrape-job label used in PromQL `{job="<scrapeJob>"}` filters
  # for etcd-self metrics. Default matches kube-prometheus-stack's
  # built-in etcd ServiceMonitor. Override if your scrape config
  # labels the etcd job differently.
  etcdScrapeJobLabel: "kube-etcd"
```

### 8.1 Schema validation (Helm `fail` invariants)

Two render-time invariants:

1. `alerts.thresholds.dbHighUsageRatio` must be `< dbCriticalUsageRatio`. A misconfiguration where warning > critical would silence the critical alert.
2. `alerts.runbookBaseUrl` must be either empty or a syntactically valid URL prefix. (Soft-validated via a regex on the scheme.)

Failure messages reference this section of the LLD just like the snapshot invariants reference LLD-phase5 §10.

---

## 9. Template structure

```yaml
{{- if and .Values.alerts.enabled (.Capabilities.APIVersions.Has "monitoring.coreos.com/v1/PrometheusRule") -}}
{{- /* validation invariants (see §8.1) */ -}}
{{- if not (lt (float64 .Values.alerts.thresholds.dbHighUsageRatio) (float64 .Values.alerts.thresholds.dbCriticalUsageRatio)) -}}
  {{- fail "alerts.thresholds.dbHighUsageRatio must be < dbCriticalUsageRatio (LLD-phase-observability §8.1)" -}}
{{- end }}
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: nkp-etcd-maintenance
  namespace: {{ .Release.Namespace }}
  labels:
    app.kubernetes.io/name: nkp-etcd-maintenance
    app.kubernetes.io/component: prometheus-rules
    app.kubernetes.io/managed-by: {{ .Release.Service }}
    helm.sh/chart: {{ include "nkp-etcd-maintenance.chart" . }}
    {{- with .Values.alerts.additionalLabels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
    {{- with .Values.commonLabels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
spec:
  groups:
    - name: nkp-etcd-maintenance.etcd-health
      rules:
        {{- if .Values.alerts.rules.EtcdMemberNoLeader.enabled }}
        - alert: EtcdMemberNoLeader
          expr: etcd_server_has_leader{job="{{ .Values.alerts.etcdScrapeJobLabel }}"} == 0
          for: {{ .Values.alerts.for.memberNoLeader }}
          labels:
            severity: {{ .Values.alerts.rules.EtcdMemberNoLeader.severity }}
            component: etcd
            {{- toYaml .Values.alerts.defaultLabels | nindent 12 }}
          annotations:
            summary: "Etcd member has no leader"
            description: "Etcd member {{`{{ $labels.instance }}`}} has reported no leader for {{ .Values.alerts.for.memberNoLeader }}; quorum may be lost."
            runbook_url: "{{ .Values.alerts.runbookBaseUrl }}#etcdmembernoleader"
            {{- toYaml .Values.alerts.defaultAnnotations | nindent 12 }}
        {{- end }}
        # ... (A2, A3, A4 in same shape) ...
    - name: nkp-etcd-maintenance.defrag
      rules:
        # ... (B1, B2) ...
    {{- if .Values.snapshot.enabled }}
    - name: nkp-etcd-maintenance.snapshot
      rules:
        # ... (C1, C2) ...
    {{- end }}
{{- end }}
```

Key template patterns:
- `{{`{{ $labels.instance }}`}}` to escape literal Go-template syntax inside PromQL templates — this prevents Helm from trying to interpret `$labels.instance` at chart-render time.
- All thresholds rendered with `printf "%g"` to avoid scientific notation (`5.24288e+08` would be valid PromQL but unreadable).
- Each rule gated on its own `.enabled` so operators can carve out subsets.

---

## 10. Dependencies on the cluster's observability stack

This addon assumes:

| Dependency | Default value | Override |
|---|---|---|
| Prometheus Operator (Coreos) CRDs installed | none — discovered at chart render via `.Capabilities.APIVersions.Has` | none needed |
| `kube-state-metrics` scraped by Prometheus, emitting `kube_job_*` and `kube_cronjob_*` metrics | yes | `alerts.rules.Etcd*JobFailed.enabled: false` to disable |
| etcd's own `/metrics` endpoint scraped, with the scrape job labelled `kube-etcd` | yes (kube-prometheus-stack default) | `alerts.etcdScrapeJobLabel: "<your-job-name>"` |
| Prometheus's `ruleSelector` matches `release: kube-prometheus-stack` | yes (kube-prometheus-stack default) | `alerts.additionalLabels` to match operator's selector |

If any of the four is missing the rule installs but Prometheus silently never picks it up. The chart can't detect this; documented in COMMANDS §"Verifying the alert is loaded".

### 10.1 Why `job="kube-etcd"` is the default

The kube-prometheus-stack ships a static config (or a Probe) that scrapes the etcd static-pod's `/metrics` endpoint and labels the scrape with `job: kube-etcd`. This is the same label the upstream kube-mixin uses, so our alerts compose with existing dashboards.

---

## 11. Decisions and rejected alternatives

| Decision | Chosen | Rejected alternatives | Reason |
|---|---|---|---|
| Resource type for alerts | `PrometheusRule` CR | ConfigMap with rule files; sidecar reload; raw rule files in Prometheus image | Operator pattern is the platform-wide standard and discovery is automatic. |
| Default enable state | `enabled: true` | `enabled: false` (opt-in) | Outcome criterion called for alerts; matching every other NKP catalog observability app (`kube-prometheus-stack-overrides`, etc.) which default-enables alert delivery. Capability gate keeps the install safe even without an operator. |
| Job-failure metric | `kube_job_status_failed > 0` | `kube_job_failed == 1` (some KSM versions); `kube_job_status_condition{condition="Failed",status="true"}` | `kube_job_status_failed` is the broadest-compatible across KSM v1.x and v2.x. The other two are valid but less portable. |
| Stale-failure handling | Accept that alert fires until `failedJobsHistoryLimit` GCs the failed Job | Time-window query filtering on `start_time` | Stale firing IS the desired behaviour — operator wants to know "most recent run failed" even if it failed yesterday. Documented; time-window alt-query provided as a tunable. |
| Custom Events from inside the container | NO | YES via kubectl-in-container or curl+SA-token | Marginal info gain vs significant surface-area increase. Native Events already cover success/fail; logs cover the why. |
| Reimplement upstream etcd mixin | NO | YES, fork the mixin and ship all ~15 alerts | Out of scope. Mixin overlaps with what the cluster's observability stack often ships separately; we'd be duplicating it. |
| Two-tier db-usage alert (`HighUsage` 70 % warning + `CriticalUsage` 90 % critical) | YES | Single `CriticalUsage` at 90 % only | Two-tier maps to operator workflows: warning = "fix soon, schedule a defrag tune", critical = "page now, NOSPACE imminent". |
| Snapshot alert severities | critical (vs defrag warning) | both warning | Recoverability beats performance. A defrag fail loses speed; a snapshot fail loses your ability to recover from disaster. |
| `runbookBaseUrl` configurable | YES | hard-code GitHub URL | Airgapped operators need to point at internal mirrors. |

---

## 12. Limitations

L1 — **Single-cluster scope.** This rule fires per-cluster. There is no fleet-roll-up; a platform team running N clusters needs to aggregate at the Alertmanager / Cortex / Thanos layer.

L2 — **Static-pod etcd only.** Same as the rest of the chart: the metric names and the `kube-etcd` scrape job label assume kubeadm-managed etcd. Managed/hosted control planes won't emit `etcd_*` metrics from this scrape job at all, so the etcd-health alerts will just never fire on those topologies. (The CronJob alerts still work because they're cluster-agnostic.)

L3 — **Depends on the cluster's Prometheus scraping etcd.** If the observability stack doesn't scrape `/metrics` on each etcd static pod, the four etcd-health alerts (A1–A4) silently never fire. The preflight Job (`kommander/preflight/topology-check-job.yaml`) does NOT currently verify this; documented as future work.

L4 — **No fragmentation-trend alert.** `EtcdHighFragmentation` is point-in-time. A slow-growth scenario where fragmentation accumulates over weeks without crossing 500 MiB will not alert. Operators wanting trend alerts should add a `predict_linear`-style rule on `etcd_mvcc_db_total_size_in_bytes` themselves.

L5 — **Restore is not automated.** Carried forward from Phase 5. The chart will never restore an etcd cluster from a snapshot; alerts inform, they do not act.

L6 — **No alert for "snapshot uploaded but to wrong bucket / wrong region".** The upload succeeds or fails as a unit; we can't tell from outside whether the object landed where the operator intended. Operators should verify the bucket independently after first install.

L7 — **`runbook_url` annotations are static.** They point at a doc that the addon ships with; if the doc is moved/renamed the annotation links rot.

---

## 13. Failure modes

| Failure | Symptom | Operator action |
|---|---|---|
| Prometheus Operator CRD not installed | Helm install succeeds; no PrometheusRule resource exists | Install kube-prometheus-stack, then `helm upgrade` to materialise the rule. |
| `ruleSelector` mismatch | Rule resource exists; Prometheus doesn't load it | `kubectl get prometheusrules -n kube-system` + `kubectl get prometheus -A -o yaml \| grep -A5 ruleSelector`. Add the matching label via `alerts.additionalLabels`. |
| etcd scrape job missing | Etcd-health alerts (A1–A4) never fire | `curl <prometheus>/api/v1/query?query=etcd_server_has_leader`. If empty, configure the ServiceMonitor for kube-etcd. |
| Threshold misconfigured (warning ≥ critical) | Helm template render fails with our `fail` invariant | Fix the values; re-render. |
| KSM not installed | Job/CronJob alerts (B1, B2, C1, C2) never fire | Install kube-state-metrics. |

---

## 14. Operator runbooks (documented in README + COMMANDS)

### 14.1 "How do I see why a Job failed?"

```bash
# Latest Jobs (defrag + snapshot):
kubectl get jobs -n kube-system | grep nkp-etcd

# Drill into a failed Job:
kubectl describe job <name> -n kube-system | tail -30      # Events
kubectl logs job/<name> -n kube-system                     # logs (defrag)
kubectl logs <pod> -n kube-system -c take-snapshot         # logs (snapshot, per phase)
kubectl logs <pod> -n kube-system -c verify-snapshot
kubectl logs <pod> -n kube-system -c upload

# All recent CronJob events:
kubectl events -n kube-system --for cronjob/nkp-etcd-defrag
kubectl events -n kube-system --for cronjob/nkp-etcd-snapshot
```

### 14.2 "How do I see if my alert rule loaded?"

```bash
# Verify the resource exists:
kubectl get prometheusrules.monitoring.coreos.com -n kube-system nkp-etcd-maintenance

# Verify Prometheus picked it up (port-forward + curl):
kubectl port-forward -n <prom-ns> svc/prometheus 9090:9090 &
curl -s localhost:9090/api/v1/rules | jq '.data.groups[] | select(.name | startswith("nkp-etcd-maintenance"))'

# Test-fire an alert manually (PromQL playground):
curl -s -G 'localhost:9090/api/v1/query' --data-urlencode 'query=etcd_server_has_leader == 0'
```

### 14.3 "How do I tune a threshold?"

```bash
helm upgrade nkp-etcd-maintenance ./nkp-etcd-maintenance \
  --namespace kube-system \
  --reuse-values \
  --set alerts.thresholds.dbHighUsageRatio=0.5 \
  --set alerts.for.dbHighUsage=2h
```

### 14.4 "How do I disable a single noisy alert?"

```bash
helm upgrade nkp-etcd-maintenance ./nkp-etcd-maintenance \
  --namespace kube-system \
  --reuse-values \
  --set alerts.rules.EtcdHighFragmentation.enabled=false
```

---

## 15. Validation plan

Before this phase is considered "Complete" in the README status table, the following must pass:

1. `helm lint .` — no errors, no warnings beyond the pre-existing "icon is recommended".
2. `helm template` in four modes:
   - Defaults (alerts on, snapshot off).
   - Snapshot on, alerts on.
   - Alerts disabled (`alerts.enabled=false`) — no PrometheusRule rendered.
   - Cluster without operator CRD (simulated with `--api-versions monitoring.coreos.com/v1`-omitted) — no rule rendered, no failure.
3. YAML parse of all renders → 100 % structural validity.
4. **promtool rule check**: feed the rendered PrometheusRule to `promtool check rules` if installed, or shell out to a containerised promtool. Reject if any rule fails to parse.
5. Helm `fail` invariants fire correctly:
   - `dbHighUsageRatio ≥ dbCriticalUsageRatio` → render fails with §8.1 reference.
6. Defrag CronJob and snapshot CronJob remain byte-identical across "alerts on/off" toggling (regression check carried over from Phase 5).
7. README and COMMANDS Markdown lint pass; all intra-doc anchors resolve.

---

## 16. Work plan (mapping to the user's three-step plan)

| User step | This LLD's deliverable | Files touched |
|---|---|---|
| Step 1 — Planning & Design | THIS document. Approved before any code. | `LLD-phase-observability.md` (new). |
| Step 2 — Scaffolding the Helm Chart Updates | (a) Add `alerts.*` block to `values.yaml` (§8). (b) Create `templates/prometheusrule.yaml` (§9). (c) Refine `upload` shell-script logs to logfmt (§5.2). | `values.yaml`, `templates/prometheusrule.yaml` (new), `templates/snapshot-cronjob.yaml` (tiny script edit). |
| Step 3 — Documentation | (a) README: rewrite "About / Quick start / Schedules / Toggle" + add "Limitations" + "Non-goals" + cross-link Manual Restore Runbook + the four runbook sub-sections (§14). (b) COMMANDS: add "Inspect & diagnose" section with the exact `kubectl` commands and expected output shapes (§14.1). | `README.md`, `COMMANDS.md`. |

After Step 3 the chart is feature-complete per the seven outcome criteria. The catalog repo update (Chart `0.4.0`, OCIRepository tag bump, defaults `cm.yaml` getting the `alerts:` block) is a separate follow-up — analogous to how Phase 5 had Step 3 catalog work but we did Step 4 docs after.

---

## 17. Open questions for the user (no blockers — defaults proposed)

| # | Question | Default I'm proposing |
|---|---|---|
| Q1 | Default schedule for the **`for:`** durations of B1 (`EtcdDefragJobFailed`)? Some teams want 5 m; some want 0 (fire immediately). | `5m` — gives the controller time to retry / surface logs. |
| Q2 | Severity routing label name — `severity` or `priority`? | `severity` (matches upstream etcd mixin and kube-prometheus-stack). |
| Q3 | Should `runbookBaseUrl` default to an internal Nutanix URL or to the public GitHub raw URL? | Public GitHub URL with a comment that operators on airgapped clusters override. |
| Q4 | Should the catalog repo's `0.2.0/` defaults `cm.yaml` get the new `alerts:` block too, or is that strictly for the upcoming `0.4.0` directory? | Strictly `0.4.0`. `0.2.0` stays defrag-only as the reviewer wanted. |

---

## 18. Sign-off

When you reply **"approved"**, I will proceed to Step 2 (chart scaffolding). I will not write any chart / doc code until you do.

---

## 19. Live-cluster validation evidence — 2026-06-12

### 19.1 Test fixture

| Item | Value |
|---|---|
| Cluster | `nkp-harsh-test-2` (3 control-plane + 2 worker, NKP v2.18.0-dev.41, K8s v1.35.2) |
| API endpoint | `https://10.22.203.236:6443` |
| Kubeconfig | `/Users/harsh.jha/nkp-cluster-3/nkp-harsh-test-2.conf` |
| Observability stack | `kube-prometheus-stack` v76.x (Grafana disabled, Prometheus retention 2h) installed into `monitoring` namespace via Helm. Footprint: ~1 GiB RAM total across `prometheus-operator`, `prometheus-0`, `alertmanager-0`, `kube-state-metrics`, `prometheus-node-exporter` × 5. |
| nkp-etcd-maintenance | Helm release `nkp-etcd-maintenance` v0.3.0 — REVISION 6 (defaults) → REVISION 7 (tightened `missedScheduleSeconds=60`, `for.*Missed=1m`) for the test, → REVISION 8 (back to defaults) after. |
| Prometheus `ruleSelector` | `{matchLabels: {release: kube-prometheus-stack}}` — matched our chart's default `alerts.additionalLabels.release` byte-for-byte; **zero override required**. |

### 19.2 Discovery / rendering proof

1. **Capability gate works.** Before kube-prometheus-stack was installed, `helm upgrade` rendered the chart without the `PrometheusRule` resource (capability gate detected the missing `monitoring.coreos.com/v1/PrometheusRule` CRD). After kube-prometheus-stack was installed, the same `helm upgrade` created the `PrometheusRule/nkp-etcd-maintenance` resource. Same `values.yaml`, different cluster capability → different rendering. Exactly as designed (§6 D3).
2. **Prometheus discovered the rule automatically.** After REVISION 6 was deployed, the resource appeared in Prometheus's rules API within ~30 seconds (one reload cycle) — no Prometheus restart, no manual reload.
3. **All 3 groups, 8 alerts loaded with `health=ok`, `state=inactive`** on the healthy cluster:

   ```
   group: nkp-etcd-maintenance.defrag
     EtcdDefragJobFailed        health=ok    state=inactive  for=300s
     EtcdDefragJobMissed        health=ok    state=inactive  for=1800s
   group: nkp-etcd-maintenance.etcd-health
     EtcdMemberNoLeader         health=ok    state=inactive  for=60s
     EtcdDbHighUsage            health=ok    state=inactive  for=3600s
     EtcdDbCriticalUsage        health=ok    state=inactive  for=300s
     EtcdHighFragmentation      health=ok    state=inactive  for=3600s
   group: nkp-etcd-maintenance.snapshot
     EtcdSnapshotJobFailed      health=ok    state=inactive  for=300s
     EtcdSnapshotJobMissed      health=ok    state=inactive  for=1800s
   ```

### 19.3 Force-fire test (4 of 8 alerts — the safe CronJob-failure set)

**Method** (T0 = `2026-06-12 11:33:35Z`):
- Applied two synthetic `Job` resources named `nkp-etcd-defrag-failtest` and `nkp-etcd-snapshot-failtest` (matching the chart's PromQL regex), `backoffLimit: 0`, `command: ["false"]`. Both went `Failed` within 30 s.
- `helm upgrade` to REVISION 7 with `alerts.thresholds.missedScheduleSeconds=60`, `alerts.for.defragJobMissed=1m`, `alerts.for.snapshotJobMissed=1m` (so the *Missed alerts could fire inside the test window without waiting 48 h).
- `kubectl patch cronjob ... suspend=true` on both maintenance CronJobs so their `lastScheduleTime` stayed stale.

**Result (T0 + 90 s = `11:35:05Z`):** the Missed alerts had already passed their tight `for: 1m` and were firing; the Failed alerts were `pending` (the chart's default `for: 5m`):

```
⏳  EtcdDefragJobFailed       state=pending  (active alerts: 1)
🔥  EtcdDefragJobMissed       state=firing   (active alerts: 1)
.   EtcdMemberNoLeader        state=inactive
.   EtcdDbHighUsage           state=inactive
.   EtcdDbCriticalUsage       state=inactive
.   EtcdHighFragmentation     state=inactive
⏳  EtcdSnapshotJobFailed     state=pending  (active alerts: 1)
🔥  EtcdSnapshotJobMissed     state=firing   (active alerts: 1)
```

**Result (T0 + ~6 min = `11:41:23Z`):** all 4 target alerts firing, all 4 etcd-health alerts inactive (passive baseline confirmed):

```
🔥  EtcdDefragJobFailed       state=firing    severity=warning   activeAt=11:34:33Z
🔥  EtcdDefragJobMissed       state=firing    severity=warning   activeAt=11:34:33Z
.   EtcdMemberNoLeader        state=inactive
.   EtcdDbHighUsage           state=inactive
.   EtcdDbCriticalUsage       state=inactive
.   EtcdHighFragmentation     state=inactive
🔥  EtcdSnapshotJobFailed     state=firing    severity=critical  activeAt=11:34:18Z
🔥  EtcdSnapshotJobMissed     state=firing    severity=critical  activeAt=11:34:18Z
```

**Per-alert labels & annotations captured from Prometheus's API at T0 + 6 min:**

| Alert | severity | component | targeting label | runbook_url |
|---|---|---|---|---|
| `EtcdDefragJobFailed` | `warning` | `etcd-maintenance` | `job_name=nkp-etcd-defrag-failtest` | `…README.md#etcddefragjobfailed` |
| `EtcdDefragJobMissed` | `warning` | `etcd-maintenance` | `cronjob=nkp-etcd-defrag` | `…README.md#etcddefragjobmissed` |
| `EtcdSnapshotJobFailed` | `critical` | `etcd-maintenance` | `job_name=nkp-etcd-snapshot-failtest` | `…README.md#etcdsnapshotjobfailed` |
| `EtcdSnapshotJobMissed` | `critical` | `etcd-maintenance` | `cronjob=nkp-etcd-snapshot` | `…README.md#etcdsnapshotjobmissed` |

Severities, label set, and per-alert runbook URLs all match the LLD design (§6 D4 + §9). The snapshot tier is correctly elevated to `critical` (per design D4 — snapshot failures degrade recoverability, not just performance).

**Alertmanager confirmation.** The 2 *Missed alerts were observed in Alertmanager's `/api/v2/alerts` endpoint with `status.state=active`. The *Failed alerts had already resolved by the time Alertmanager was queried because the synthetic `Job` resources hit their `ttlSecondsAfterFinished: 1800` (30 min) and were garbage-collected; this is a property of the **test fixture**, not the alert — the alert behaves identically on a real failed maintenance Job because the chart sets `ttlSecondsAfterFinished: 86400` (24 h) on its own Jobs, well beyond the typical operator-response window.

### 19.4 Validation outcomes

| Outcome criterion (§3) | Live evidence |
|---|---|
| **A** — alerts deploy as a single `PrometheusRule` with 3 groups | ✓ resource visible at `kubectl get prometheusrule nkp-etcd-maintenance -n kube-system`; 3 groups, 8 rules. |
| **B** — capability-gated on the CRD | ✓ rule absent before kube-prometheus-stack install; present after; no other config changed. |
| **C** — discovered by Prometheus via default `release: kube-prometheus-stack` label | ✓ rule appeared in `/api/v1/rules` within ~30 s of `helm upgrade`. |
| **D** — `EtcdDefragJobFailed`, `EtcdDefragJobMissed`, `EtcdSnapshotJobFailed`, `EtcdSnapshotJobMissed` fire on real failure conditions | ✓ all 4 transitioned `inactive → pending → firing` per the `for:` clock; severities/labels/annotations match §9. |
| **E** — etcd-health alerts do NOT fire on a healthy cluster | ✓ all 4 stayed `inactive` throughout the test (passive baseline). |
| **F** — fail-fast invariant on `dbHighUsageRatio < dbCriticalUsageRatio` | (unit-tested earlier with `helm template --set` — see Step 2 verification matrix). |
| **G** — `dbHighUsageRatio`, `for.*` etc. can be overridden at install time | ✓ REVISION 7 demonstrated live override of `missedScheduleSeconds` and `for.defragJobMissed` / `for.snapshotJobMissed` via `--set`. |

### 19.5 Open items deferred to future validation

- **Etcd-self alert firing (`EtcdMemberNoLeader`, `EtcdDbHighUsage`, `EtcdDbCriticalUsage`, `EtcdHighFragmentation`)** — these were validated **passively** (they did not misfire on a healthy cluster), not **actively** (we did not break quorum or stuff etcd with data to provoke them). Active validation requires either a scratch cluster (acceptable to break) or accepting >1 GiB of synthetic ConfigMap churn on a real cluster. Recommended as a follow-up on the next disposable test cluster.
- **kube-prometheus-stack's own `etcd` ruleset** — kps ships an `etcd` PrometheusRule (the upstream etcd-mixin) with a partially overlapping alert set (different names, different thresholds). Our chart's 4 etcd-health alerts are deliberately additive — they target maintenance-specific symptoms (`EtcdHighFragmentation` is maintenance-specific; the upstream mixin's `etcdHighNumberOfFailedHTTPRequests` is not). Operators with the upstream mixin already enabled can disable individual chart alerts via `alerts.rules.<AlertName>.enabled=false` (validated via local helm template in Step 2, not re-validated live).
- **Alertmanager routing rules / receiver delivery** — out of scope for this phase. Alertmanager observed the alerts in `/api/v2/alerts`; whether they reach Slack/PagerDuty depends on operator-provided receiver configuration.

### 19.6 Test fixture left on the cluster after this validation run

| Item | State at end of test |
|---|---|
| `helm release nkp-etcd-maintenance` | REVISION 8 — default values, `snapshot.enabled=true`, `snapshot.s3.enabled=false`, `alerts.*` at chart defaults. |
| `cronjob/nkp-etcd-defrag` | `SUSPEND=False` — restored. |
| `cronjob/nkp-etcd-snapshot` | `SUSPEND=False` — restored. |
| Synthetic `Job` resources `nkp-etcd-*-failtest` | deleted. |
| `kube-prometheus-stack` Helm release in `monitoring` namespace | **left in place** for re-use during further development. Uninstall with `helm uninstall kube-prometheus-stack -n monitoring && kubectl delete ns monitoring` when no longer needed. |
