# Upgrading the kube-prometheus-stack fork

We fork the upstream [Prometheus Community Kubernetes Helm Charts](https://github.com/prometheus-community/helm-charts) and maintain a set of patches in the [patch/mesospere](./patch/mesosphere) folder. That folder houses all of the templates, hooks, dashboards, etc. we deploy in the prometheus addon in KBA.

## Upgrading

To upgrade the operator, simply run:
```sh
./upgrade_operator.sh
```

The upgrade script:
- clones the prometheus-community/helm-charts repo and checks out a configured tag
- copies all the files belonging to the kube-prometheus-stack chart
- replaces all the files, of the same name, in this fork with the newer upstream versions; adds the files if they're new.
- applies all the patches stored in the [/patch](./patch) folder.
  - note: each of these patch files adds a git commit message when applied. This makes it easier to review as each commit will show what changes were needed.
