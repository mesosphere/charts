# Upgrading the istio-helm fork charts

We pull the upstream Istio Helm charts and maintain a small set of
customizations on top. The five wrapper charts each wrap one upstream chart:

| Wrapper chart        | Vendored sub-chart                         | Upstream chart |
| -------------------- | ------------------------------------------ | -------------- |
| `istio-helm-base`    | `charts/base`                              | `base`         |
| `istio-helm-cni`     | `charts/cni`                               | `cni`          |
| `istio-helm-gateway` | `charts/gateway`                           | `gateway`      |
| `istio-helm-istiod`  | `charts/istiod`                            | `istiod`       |
| `istio-helm-ztunnel` | `charts/ztunnel`                           | `ztunnel`      |

## How customizations are modelled

**The live chart is the single source of truth.** A "customization" is not a
separate artifact you maintain - it is simply however the vendored sub-chart
(`staging/istio-helm-<name>/charts/<name>`) differs from the upstream Istio
chart it was pulled from. There are no `.patch` files and no overlay store.

Conceptually a customization is one of:

- a **new file** we added that upstream does not ship, or
- a **modification** to a file upstream owns.

`upgrade.sh` re-derives both automatically at upgrade time (see below), so
there is nothing to keep in sync.

## Upgrading

Prerequisites: `git` and `helm` (>= 3.8, for OCI) plus standard POSIX tools
(`bash`, `sed`, `find`, `cmp`, `mktemp`) on `PATH`. Run on a **clean working
tree / dedicated branch** - on any error the script hard-resets to the starting
commit and discards uncommitted changes.

To upgrade, run:

```sh
./upgrade.sh 1.30.0     # or pass a tag explicitly
```

For each chart the script:

- reads the Istio version we are **currently on** from the wrapper
  `Chart.yaml` `appVersion` (the "base"), and `helm pull`s both the base and
  the target upstream charts from the published OCI registry
  (`oci://gcr.io/istio-release/charts/<name>`);
- computes our delta = how the live chart differs from the **base** upstream,
  and replays it onto the **target** upstream with a 3-way merge (`git
  merge-file`). Files only we changed are re-applied; files only upstream
  changed are taken as-is; a genuine line-level overlap is a conflict;
- swaps the merged result in for `charts/<name>`;
- bumps the wrapper-level Istio version references (each wrapper `Chart.yaml`
  `appVersion` + the vendored sub-chart dependency `version`, and the pinned
  image `tag` in the wrapper `values.yaml`) from the old tag to the new tag.
  Mesosphere sub-chart versions (grafana/prometheus-operator/security) and the
  kubectl image tags are left untouched because they never equal the Istio tag;
- commits one change per chart.

### Conflicts

A conflict is only possible for the second kind of customization - an edit to a
file upstream also owns. New files we add never conflict (there is nothing
upstream to disagree with). For an edited file, if the target upstream changed
the exact lines our customization touches, the 3-way merge cannot decide for us.
In that case the run **stops**, leaves standard `<<<<<<< / ======= / >>>>>>>`
markers in the affected files, prints the list, and does **not** commit. Resolve
the markers, then commit.

This loud stop is deliberate. Re-applying an edit to an upstream-owned file has
no free lunch: a stored `.patch` would reject, a frozen full-file copy would
silently discard upstream's change, and the 3-way merge surfaces it as a
conflict. Surfacing it is the safe choice. In practice patch-level bumps (e.g.
1.29.0 -> 1.29.2) merge with no conflicts; they mainly appear on larger jumps
where upstream reworked a file we also edit.

On any *other* error the working tree is rolled back to the starting revision
via a `trap` (the script uses `set -Eeuo pipefail` so the trap also fires for
failures inside helper functions such as `helm pull`).

### Manual steps after running

- Bump each wrapper `Chart.yaml` `version:` (the chart *packaging* version, e.g.
  `1.25.0`). This is a release-management decision, independent of the Istio
  version, so the script does not touch it.
- Review downstream value overrides in
  [kommander-applications](https://github.com/mesosphere/kommander-applications)
  (the `istio-*` HelmRelease `values`/ConfigMaps). See "Downstream
  compatibility" below.

> We pull the **published** Helm charts rather than the git source on purpose:
> the published charts already point at `docker.io/istio` with the release tag
> and carry the normalized `Chart.yaml`, which is exactly what we vendor. This
> keeps the upgrade a pure re-vendor with no version/registry rewriting, and
> lets us pull the base version too for an exact 3-way merge.

## Current customizations

These are the deltas the merge re-applies on top of upstream. Keep this table
in sync when adding or removing customizations. (This table is documentation;
the actual source of truth is the chart content itself.)

| Chart   | Type     | File                                                | Purpose                                                       |
| ------- | -------- | --------------------------------------------------- | ------------------------------------------------------------- |
| base    | new file | `templates/namespace.yaml`                          | Create the configurable `global.istioNamespace`              |
| gateway | new file | `templates/_additional_helpers.tpl`                 | Helpers for the additional-gateway support                    |
| gateway | modify   | `values.yaml`, `values.schema.json`                 | `proxy.image` and `additional_gateways: []` config surface    |
| gateway | modify   | `templates/deployment.yaml`                         | Configurable proxy image + additional-gateway Deployments     |
| gateway | modify   | `templates/{hpa,poddisruptionbudget,role,service,serviceaccount}.yaml` | Render the same resources for each additional gateway |
| istiod  | new file | `templates/zipkin-svc.yaml`                         | Zipkin/Jaeger tracing service                                 |
| ztunnel | new file | `templates/ambient-migration-hook.yaml`            | Helm hook Job for sidecar-to-ambient migration                |
| ztunnel | modify   | `values.yaml`                                       | `migration.*` values                                          |
| ztunnel | modify   | `files/profile-ambient.yaml`                        | Enable migration hook under the ambient profile               |

### Mesosphere-only sub-charts (istiod)

`istio-helm-istiod` also ships three sub-charts that are entirely ours and have
no upstream counterpart: `charts/security` (cert-manager CA integration),
`charts/grafana` (dashboards) and `charts/prometheus-operator` (ServiceMonitors).
They are siblings of `charts/istiod`, so re-vendoring `istiod` does not touch
them. Maintain them directly. The grafana dashboards were carried forward from
the legacy `staging/istio` operator chart; refresh them from upstream
`manifests/addons/dashboards` only when intentionally updating dashboards.

## Downstream compatibility (kommander-applications)

These charts are consumed by
[kommander-applications](https://github.com/mesosphere/kommander-applications),
which supplies `values` overrides via the `istio-*` HelmReleases/ConfigMaps.

The **wrapper `values.yaml`** of each chart is the stable interface downstream
depends on (e.g. `global.istioNamespace`, `gateway.*`, `istiod.*`,
`security.*`, `ztunnel.*`). The upgrade does not change the *shape* of that
interface, so a routine patch bump (e.g. 1.29.0 -> 1.29.2) is transparent to
downstream.

The risk is a **major/minor Istio upgrade that renames or restructures an
upstream value key** we forward. Because we re-vendor the upstream
`values.yaml`, such a change is picked up automatically, and any downstream
override that still sets the old key would silently stop taking effect. To
guard against this on every upgrade:

- Diff the vendored `charts/<name>/values.yaml` against the previous version
  (the per-chart upgrade commit makes this a one-line `git show`).
- Cross-check the keys that kommander-applications overrides against the new
  upstream schema (also `values.schema.json` for gateway).
- Render with the downstream values (`helm template ... -f <downstream-values>`)
  and diff the output before/after.

Keys we deliberately expose and must keep stable (add here as they change):
`global.hub`, `global.tag`, `global.istioNamespace`, `global.imagePullPolicy`,
`global.priorityClassName`, `gateway.proxy.image`, `gateway.additional_gateways`,
`istiod.*`, `security.image`, `security.tag`, `security.issuerName`,
`ztunnel.hub`, `ztunnel.tag`, `ztunnel.migration.*`.

## Managing a new wrapper chart

Add its name to the `CHARTS` list in [`lib/charts.sh`](./lib/charts.sh); that
single list drives `upgrade.sh`.

> Note: the merge represents additions and modifications, and handles files we
> delete relative to upstream. If upstream *removes* a file we had modified, the
> script keeps our copy and prints a note so you can decide what to do.
