# Upgrading the docker-registry fork

We fork the upstream [Docker Registry Helm Chart](https://github.com/twuni/docker-registry.helm) and maintain a set of patches in the [patch/nutanix](./patch/nutanix) folder.

## Upgrading

To upgrade the operator, simply run:
```sh
./upgrade.sh
```

The upgrade script:
- clones the helm/charts repo `master` branch
- copies all the files under `staging/docker-registry/`
- replaces all the files, of the same name, in this fork with the newer upstream versions; adds the files if they're new.
- applies all the patches stored in the [/patch](./patch) folder.
  - note: each of these patch files adds a git commit message when applied. This makes it easier to review as each commit will show what changes were needed.
