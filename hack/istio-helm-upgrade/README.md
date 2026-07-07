# istio-helm upgrade tooling

Automation for upgrading the Istio (Helm based) charts

## Upgrading

Run from `hack/istio-helm-upgrade/`:

```sh
./upgrade.sh              # upgrade to the pinned DEFAULT_ISTIO_TAG in the script
./upgrade.sh 1.30.0       # upgrade to a specific tag
ISTIO_TAG=1.30.0 ./upgrade.sh
```

What it does, per chart:

1. `helm pull` the upstream chart we are currently on (the **base**) and the
  target upstream, both from `oci://gcr.io/istio-release/charts/<name>`.
2. Derive our delta = how the live chart differs from the base upstream, and
  **3-way merge** it onto the target upstream. Upstream's own changes are
   preserved; only a genuine line-level overlap becomes a conflict.
3. Bump the wrapper-level Istio version references (`Chart.yaml` appVersion +
  sub-chart dependency version, and image `tag` in `values.yaml`).
4. Commit one change per chart.

If one of our edits and an upstream change land on the same lines, the run stops
with conflict markers for you to resolve (rare; newly added files never
conflict). Any other error rolls the tree back. See [UPGRADING.md](./UPGRADING.md)
for details.

After it finishes: bump each wrapper `Chart.yaml` `version:` (chart packaging
version) per release convention, and review downstream overrides. See
[UPGRADING.md](./UPGRADING.md) for the full flow, the customization inventory,
and downstream (kommander-applications) compatibility notes.

## Managing a new wrapper chart

Add its name to the `CHARTS` list in [lib/charts.sh](./lib/charts.sh) - that
single list drives the whole upgrade.

> Mesosphere-only sub-charts that have no upstream counterpart (istiod's
> `security` / `grafana` / `prometheus-operator`) are siblings of
> `charts/<name>`, so they are never re-vendored and are maintained directly.

## Layout

```
hack/istio-helm-upgrade/
├── upgrade.sh          # upgrade to a tag (pull base + target, merge, bump, commit)
├── README.md           # this file
├── UPGRADING.md        # detailed reference
└── lib/
    ├── charts.sh       # single source of truth: the managed chart list
    └── helpers.sh      # shared shell helpers (pull, 3-way replay, commit, bump)
```

