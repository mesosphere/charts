# Chaos recipe — force-fire the 4 `etcd-health` alerts on a live cluster

This recipe walks you, end-to-end, through actively triggering the four
`etcd-health` alerts shipped by `nkp-etcd-maintenance`. **Live-validated
on `nkp-harsh-test-2` on 2026-06-14**; see § "Live run evidence" at the
bottom for captured JSON + alert states.

| Alert | Trigger method in this recipe |
|---|---|
| `EtcdDbHighUsage` | lower `dbHighUsageRatio` to a level the live DB already exceeds |
| `EtcdDbCriticalUsage` | lower `dbCriticalUsageRatio` to a level the live DB already exceeds |
| `EtcdHighFragmentation` | lower `highFragmentationBytes` to a level the natural `db_total − db_in_use` delta already exceeds |
| `EtcdMemberNoLeader` | partition tcp/2380 (etcd peer) on **one follower** with an ssh-less privileged Pod |

> **Why threshold-lowering for the capacity alerts?**
> Stuffing real data into etcd to cross the 70 %/90 % default thresholds on
> a 2 GiB quota means writing >1 GiB of ConfigMaps. That's not chaos; that's
> production damage. Lowering thresholds, observing the fire, and restoring
> defaults is the same logical test (Prometheus evaluates `expr > threshold`
> identically either way) with **zero etcd write amplification**.
>
> **Why a partition for `NoLeader`?**
> `kill -STOP <etcd-pid>` freezes the metrics endpoint too, so
> `etcd_server_has_leader` stops being scraped instead of evaluating to 0 —
> the alert can't fire on `absent()` because the alert expression is
> `etcd_server_has_leader == 0`, not `absent(etcd_server_has_leader)`.
> Dropping tcp/2380 keeps metrics scrapable AND breaks peer comms — the
> partitioned member explicitly publishes `has_leader=0`.

---

## Pre-conditions

1. `nkp-etcd-maintenance` v0.2.0+ installed in `kube-system`.
2. kube-prometheus-stack running (`monitoring` namespace on this cluster; check yours with `kubectl get ns | grep -i prom`).
3. **etcd `/metrics` must be reachable from Prometheus** — see Step 0.
4. 3 (or 5/7) control-plane nodes — recipe assumes ≥3 so a single-member partition keeps quorum.

---

## Step 0 — verify etcd metrics are scrapable (one-time per cluster)

This was the **#1 gotcha** during live validation. NKP/kubeadm defaults to
`--listen-metrics-urls=http://127.0.0.1:2381` on etcd, so kube-prometheus-stack's
kubeEtcd targets show `connection refused` on the node IP. Without this fix,
Prometheus has **zero etcd series** and the alerts can never evaluate.

### 0a. Diagnose

```bash
PROM='/api/v1/namespaces/monitoring/services/kube-prometheus-stack-prometheus:9090/proxy'

# Expect: returns "3" (one series per CP). If empty -> etcd not scraped.
kubectl get --raw "${PROM}/api/v1/query?query=count(etcd_server_has_leader)" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["data"])'

# Scrape target health:
kubectl get --raw "${PROM}/api/v1/targets?state=any" \
  | python3 -c '
import sys, json
for t in json.load(sys.stdin)["data"]["activeTargets"]:
    if "etcd" not in t["labels"]["job"].lower(): continue
    print(t["scrapeUrl"], t["health"], (t.get("lastError") or "")[:80])
'
```

If any target shows `down` with `connection refused`, run Step 0b.

### 0b. Fix: roll `--listen-metrics-urls=http://0.0.0.0:2381` to every CP node

Uses the same chassis as `etcd-quota-bumper`: privileged Pod with hostPath on
`/etc/kubernetes/manifests`, atomic file swap, dot-prefix backup so kubelet
doesn't shadow the active manifest. Reversible by restoring the `.bak.*`
file.

```bash
TEMPLATE=docs/chaos/etcd-metrics-listen-fixer.yaml
for NODE in $(kubectl get node -l node-role.kubernetes.io/control-plane -o jsonpath='{range .items[*]}{.metadata.name} {end}'); do
  TAG=$(echo "$NODE" | tr '.' '-' | tail -c 12)
  echo "==> patching $NODE"
  sed -e "s/REPLACE_NODE/$NODE/" -e "s/REPLACE_TAG/$TAG/" "$TEMPLATE" \
    | kubectl apply -f -

  # Wait for kubelet to pick up the manifest change (file-check-frequency = 20s).
  for i in $(seq 1 10); do
    sleep 12
    cur=$(kubectl -n kube-system get pod "etcd-${NODE}" \
            -o jsonpath='{range .spec.containers[?(@.name=="etcd")].command[*]}{@}{"\n"}{end}' \
          | grep listen-metrics-urls)
    case "$cur" in
      *0.0.0.0*) echo "  -> restarted ($cur)"; break ;;
      *)         echo "  ... wait $i"; ;;
    esac
  done
done

# Cleanup the helper pods
kubectl -n kube-system delete pod -l app.kubernetes.io/component=etcd-metrics-listen-fixer

# Re-verify: now count() should return 3, targets all up.
kubectl get --raw "${PROM}/api/v1/query?query=count(etcd_server_has_leader)" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["data"])'
```

> **Don't roll the flag flip in parallel.** Doing one node at a time keeps
> quorum: at any moment only one etcd member is restarting, and the
> remaining 2/3 vote. Parallel restart would risk a brief quorum loss.

---

## Step 1 — open one terminal per UI for screenshots

```bash
# Terminal A — Prometheus UI on http://localhost:9090
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090

# Terminal B — Alertmanager UI on http://localhost:9093
kubectl -n monitoring port-forward svc/kube-prometheus-stack-alertmanager 9093:9093
```

Keep these open for the rest of the test.

---

## Step 2 — capture the baseline

```bash
PROM='/api/v1/namespaces/monitoring/services/kube-prometheus-stack-prometheus:9090/proxy'

# Baseline ratio per instance — pick chaos thresholds JUST below these
kubectl get --raw "${PROM}/api/v1/query?query=etcd_mvcc_db_total_size_in_bytes%20/%20etcd_server_quota_backend_bytes" \
  | python3 -c '
import sys,json
for r in json.load(sys.stdin)["data"]["result"]:
    print(f"  {r[\"metric\"][\"instance\"]:<25} ratio={r[\"value\"][1]}")
'

# Baseline fragmentation in bytes per instance
kubectl get --raw "${PROM}/api/v1/query?query=etcd_mvcc_db_total_size_in_bytes%20-%20etcd_mvcc_db_total_size_in_use_in_bytes" \
  | python3 -c '
import sys,json
for r in json.load(sys.stdin)["data"]["result"]:
    print(f"  {r[\"metric\"][\"instance\"]:<25} bytes={r[\"value\"][1]}")
'
```

On `nkp-harsh-test-2` during live validation we saw ~1.9 % ratio per
instance and ~40 MB fragmentation per instance. Set chaos thresholds **just
below** those numbers so the alerts fire from your *actual* cluster
state, not from synthetic data.

**Defaults that fire on any non-empty cluster:**
- `dbHighUsageRatio=0.01` (1 % — every cluster's etcd is bigger than this)
- `dbCriticalUsageRatio=0.015` (1.5 %)
- `highFragmentationBytes=1048576` (1 MiB)

If your baseline is lower than this, drop the chaos values further.

---

## Step 3 — lower thresholds + shorten `for:` durations

```bash
helm upgrade nkp-etcd-maintenance ./nkp-etcd-maintenance \
  --namespace kube-system --reuse-values \
  --set alerts.thresholds.dbHighUsageRatio=0.01 \
  --set alerts.thresholds.dbCriticalUsageRatio=0.015 \
  --set alerts.thresholds.highFragmentationBytes=1048576 \
  --set alerts.for.memberNoLeader=30s \
  --set alerts.for.dbHighUsage=30s \
  --set alerts.for.dbCriticalUsage=30s \
  --set alerts.for.highFragmentation=30s
```

Verify the PrometheusRule was patched:

```bash
kubectl -n kube-system get prometheusrule nkp-etcd-maintenance \
  -o jsonpath='{range .spec.groups[*].rules[*]}{.alert}{"  "}{.expr}{"\n"}{end}' \
  | grep -E '^Etcd(Db|HighFrag)'
```

Expect:

```
EtcdDbHighUsage       (...) > 0.01
EtcdDbCriticalUsage   (...) > 0.015
EtcdHighFragmentation (...) > 1048576
```

Wait ~75 s (one `for:` window + one Prometheus eval cycle), then:

```bash
# Screenshot point #1 — three capacity alerts firing
open http://localhost:9090/alerts          # search "Etcd"
open http://localhost:9093/#/alerts        # Alertmanager

# CLI confirmation:
kubectl get --raw "${PROM}/api/v1/alerts" \
  | python3 -c '
import sys, json
alerts = {}
for a in json.load(sys.stdin)["data"]["alerts"]:
    n = a["labels"]["alertname"]
    if not n.startswith("Etcd"): continue
    alerts.setdefault(n, []).append(a)
for n in sorted(alerts):
    print(f"  {n}: {len(alerts[n])} firing")
'
```

Expected: `EtcdDbHighUsage: 3 firing`, `EtcdDbCriticalUsage: 3 firing`,
`EtcdHighFragmentation: 3 firing`. (1 firing per CP member × 3 members.)

---

## Step 4 — partition tcp/2380 on **one follower** to fire `EtcdMemberNoLeader`

### 4a. Identify the current leader and a follower

```bash
ETCD_POD=$(kubectl -n kube-system get pod -l component=etcd -o jsonpath='{.items[0].metadata.name}')

kubectl -n kube-system exec "$ETCD_POD" -c etcd -- etcdctl \
  --endpoints https://127.0.0.1:2379 \
  --cacert /etc/kubernetes/pki/etcd/ca.crt \
  --cert  /etc/kubernetes/pki/etcd/server.crt \
  --key   /etc/kubernetes/pki/etcd/server.key \
  endpoint status --cluster -w table
```

Find the row with `IS LEADER = true`. Pick **any other row** (a follower).
Map its etcd endpoint IP back to a node name:

```bash
# Map 10.22.202.88 (a follower IP) to a node name:
kubectl get node -o wide \
  | awk '$6=="10.22.202.88" {print $1}'
```

> **Never partition the leader.** Partitioning a follower loses 1/3 votes
> and the cluster keeps quorum. Partitioning the leader forces an election
> on the remaining 2/3, which works but is more disruptive.

### 4b. Schedule the chaos Pod

```bash
FOLLOWER=<node-name-from-4a>

sed "s/REPLACE_ME_WITH_FOLLOWER_NODE/${FOLLOWER}/" \
  docs/chaos/etcd-peer-partition.yaml \
  | kubectl apply -f -

# Watch its logs in a separate terminal:
kubectl -n kube-system logs -f pod/etcd-peer-partition
```

Expected log:

```
[HH:MM:SSZ] installing chaos rules on <node>
[HH:MM:SSZ] rules installed:
   ... DROP tcp dpt:2380 /* chaos-test-2380 */
[HH:MM:SSZ] partition active; sleeping 180s then auto-cleaning
```

### 4c. Watch `has_leader` flip + `EtcdMemberNoLeader` fire

```bash
# t+10s: partitioned member's has_leader flips to 0:
kubectl get --raw "${PROM}/api/v1/query?query=etcd_server_has_leader" \
  | python3 -c '
import sys,json
for r in json.load(sys.stdin)["data"]["result"]:
    print(f"  {r[\"metric\"][\"instance\"]:<25} has_leader={r[\"value\"][1]}")
'
# Expect one instance with has_leader=0; the other two with =1.

# t+45s: EtcdMemberNoLeader fires (for: 30s clears).
kubectl get --raw "${PROM}/api/v1/alerts" \
  | python3 -c '
import sys,json
for a in json.load(sys.stdin)["data"]["alerts"]:
    if a["labels"]["alertname"] == "EtcdMemberNoLeader":
        print(f"  state={a[\"state\"]} instance={a[\"labels\"].get(\"instance\")} activeAt={a.get(\"activeAt\")}")
'
```

**Screenshot point #2** — all 4 etcd-health alerts firing simultaneously.

### 4d. Cleanup the partition

The chaos Pod self-heals at t+180s. To finish early:

```bash
kubectl -n kube-system delete pod etcd-peer-partition
# preStop hook runs (10s grace) and removes the iptables rules.
```

Confirm `has_leader=1` returns to all 3 members within ~10 s of cleanup.

---

## Step 5 — full cleanup: restore default thresholds + durations

```bash
helm upgrade nkp-etcd-maintenance ./nkp-etcd-maintenance \
  --namespace kube-system --reuse-values \
  --set alerts.thresholds.dbHighUsageRatio=0.7 \
  --set alerts.thresholds.dbCriticalUsageRatio=0.9 \
  --set alerts.thresholds.highFragmentationBytes=524288000 \
  --set alerts.for.memberNoLeader=1m \
  --set alerts.for.dbHighUsage=1h \
  --set alerts.for.dbCriticalUsage=5m \
  --set alerts.for.highFragmentation=1h
```

**Screenshot point #3** — wait ~60 s, all 4 etcd-health alerts back to
`inactive`.

```bash
kubectl get --raw "${PROM}/api/v1/alerts" \
  | python3 -c '
import sys,json
ds = [a for a in json.load(sys.stdin)["data"]["alerts"] if a["labels"]["alertname"].startswith("Etcd")]
print(f"  active Etcd* alerts: {len(ds)}")
'
# Expected output: "active Etcd* alerts: 0"
```

> **Note on Step 0:** The `--listen-metrics-urls=0.0.0.0:2381` flag flip
> from Step 0b stays in place. That's intentional — it leaves your cluster
> with permanent etcd monitoring on. If you want to revert, run Step 0b
> with the inverse sed (`0.0.0.0` → `127.0.0.1`).

---

## Live run evidence (2026-06-14, `nkp-harsh-test-2`)

Captured via `kubectl get --raw` against Prometheus + Alertmanager during
the partition window:

| Source | File | What it shows |
|---|---|---|
| Prometheus | `evidence/prom-alerts.json` | 10 active firings: 3× DbHigh + 3× DbCritical + 3× HighFrag + 1× MemberNoLeader |
| Prometheus | `evidence/prom-rules.json` | Full rules + per-rule state snapshot |
| Alertmanager | `evidence/am-alerts.json` | Same 10 alerts visible at AM with `state=active` |
| Promql | `evidence/has_leader.txt` | After cleanup: 1/1/1 |
| Promql | `evidence/db_ratio.txt` | ~1.9 % per member (baseline) |
| Promql | `evidence/frag_bytes.txt` | ~40 MB per member (baseline) |

Summary of `prom-alerts.json` at the firing peak:

```
EtcdDbCriticalUsage:   3 firing  (1 per instance, severity=critical, activeAt=16:27:14Z)
EtcdDbHighUsage:       3 firing  (1 per instance, severity=warning,  activeAt=16:27:14Z)
EtcdHighFragmentation: 3 firing  (1 per instance, severity=warning,  activeAt=16:27:14Z)
EtcdMemberNoLeader:    1 firing  (instance 10.22.202.88, severity=critical, activeAt=16:29:44Z)
```

Alertmanager `startsAt` is the alert's "for: 30s" boundary — 30 s after
the Prometheus `activeAt`, exactly as configured.

---

## Quick reference — 30-second invocation (Steps 3-5 only)

Assumes Step 0 has been completed once (etcd metrics scrapable).

```bash
# 1) Lower the bar
helm upgrade nkp-etcd-maintenance ./nkp-etcd-maintenance -n kube-system --reuse-values \
  --set alerts.thresholds.dbHighUsageRatio=0.01 \
  --set alerts.thresholds.dbCriticalUsageRatio=0.015 \
  --set alerts.thresholds.highFragmentationBytes=1048576 \
  --set alerts.for.memberNoLeader=30s \
  --set alerts.for.dbHighUsage=30s \
  --set alerts.for.dbCriticalUsage=30s \
  --set alerts.for.highFragmentation=30s

# 2) Partition one follower
ETCD_POD=$(kubectl -n kube-system get pod -l component=etcd -o jsonpath='{.items[0].metadata.name}')
LEADER_IP=$(kubectl -n kube-system exec "$ETCD_POD" -c etcd -- etcdctl \
  --endpoints https://127.0.0.1:2379 \
  --cacert /etc/kubernetes/pki/etcd/ca.crt \
  --cert /etc/kubernetes/pki/etcd/server.crt \
  --key  /etc/kubernetes/pki/etcd/server.key \
  endpoint status --cluster -w json \
  | python3 -c 'import sys,json; print([m["Endpoint"] for m in json.load(sys.stdin) if m["Status"]["leader"]==m["Status"]["header"]["member_id"]][0])' \
  | sed 's|https://||;s|:2379||')
FOLLOWER=$(kubectl get node -o jsonpath='{range .items[*]}{.metadata.name} {.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}' \
  | grep -v " ${LEADER_IP}$" | grep -E '(control-plane|master)' | head -1 | awk '{print $1}')
# If the grep above returns empty (cluster uses different role labels), set FOLLOWER manually.
sed "s/REPLACE_ME_WITH_FOLLOWER_NODE/${FOLLOWER}/" docs/chaos/etcd-peer-partition.yaml | kubectl apply -f -
sleep 60   # all 4 alerts should be firing by now

# 3) Cleanup
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

---

## Validation status

- [x] **Offline:** `helm template` with chaos overrides renders all 4 alert
      `expr:` and `for:` exactly as expected.
- [x] **Offline:** Chaos Pod YAML passes structural validation.
- [x] **Live (2026-06-14, `nkp-harsh-test-2`):** all 4 etcd-health alerts
      observed firing in both Prometheus and Alertmanager, cleanup verified
      back to inactive. See `docs/chaos/evidence/`.
- [x] **Discovered (Step 0):** NKP/kubeadm defaults to
      `--listen-metrics-urls=http://127.0.0.1:2381`; without flipping to
      `0.0.0.0:2381` no etcd-health alert can ever fire. Added Step 0 to
      this recipe.

---

## Files referenced by this recipe

```
docs/chaos/
├── CHAOS-RECIPE.md                    # this file
├── etcd-metrics-listen-fixer.yaml     # Step 0b: rolling --listen-metrics-urls patch
├── etcd-peer-partition.yaml           # Step 4: ssh-less partition Pod
└── evidence/
    ├── prom-alerts.json               # 10 alert firings during partition
    ├── prom-rules.json                # PrometheusRule state snapshot
    ├── am-alerts.json                 # Alertmanager view of same 10 alerts
    ├── has_leader.txt
    ├── db_ratio.txt
    └── frag_bytes.txt
```
