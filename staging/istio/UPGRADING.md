# Upgrading the istio fork

We fork the upstream [Istio Operator Helm Chart](https://github.com/istio/istio/tree/master/manifests/charts/istio-operator) and maintain a set of patches in the [patch/](./patch/) folder. That folder houses all of the additional and patched templates we deploy in the Istio application.

## Upgrading

To upgrade the istio operator, simply run:
```sh
./upgrade_operator.sh
```

The upgrade script:
- clones the istio/istio repo and checks out a configured tag (update the `ISTIO_TAG` env var in the upgrade_operator.sh script and first push that commit)
- copies all the files belonging to the upstream istio-operator helm chart
- replaces all the files, of the same name, in this fork with the newer upstream versions; adds the files if they're new.
- adds any new template files stored in the [/patch/templates](./patch/templates) folder.
- applies all the patches stored in the [/patch/patches](./patch/patches) folder.
    - note: each of these patch files adds a git commit message when applied. This makes it easier to review as each commit will show what changes were needed.
