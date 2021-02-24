# Kommander
Represents an umbrella chart for deploying multiple charts:
- Kommander-Karma
- Kommander-Thanos
- Grafana
- Kommander-Cluster-Lifecycle
- Kommander-ui
- Kubeaddons-Catalog

## Pre-Reqs for Installation
You must have installed in your cluster `Cert-Manager`.

```bash
CERT_MANAGER_VERSION=0.10.1
kubectl apply -f https://raw.githubusercontent.com/jetstack/cert-manager/v${CERT_MANAGER_VERSION}/deploy/manifests/00-crds.yaml;
helm repo add jetstack https://charts.jetstack.io;
helm repo update;
helm install jetstack/cert-manager --name cert-manager --version="${CERT_MANAGER_VERSION}" --namespace cert-manager;
```

## Install Chart with a known Issuer
```bash
helm install --namespace "kommander" --name "kommander-kubeaddons" --set kommander-cluster-lifecycle.certificates.issuer.name="issuer-name" ./stable/kommander
```

## Install Locally with self-signed Certificate
```bash
helm install --namespace "kommander" --name "kommander-kubeaddons" --set kommander-cluster-lifecycle.certificates.issuer.selfSigned=true ./stable/kommander
```

## Backporting / Patch Releases
The minor version should be bumped following every Kommander release.

- Kommander v1.4.x -> chart version v0.16.x
- Kommander v1.3.x patches should go into chart version v0.15.x

This allows us to backport and create patch releases. When backporting, you should work off of the appropriate release branch for the chart. The release branch follows a `release/kommander-v0.15.x` convention for v0.15.x chart versions. If the release branch does not exist, you must create it. Browse the chart's git history until you find the commit before the chart was bumped to the next minor version. Branch off that commit to create the release branch, which will sit at the latest patch version of the chart before it was bumped to the next minor version (and release of Kommander).

Push this release branch to the m/charts repo. Then, branch off the release branch to backport your changes. Open up a PR against the release branch. When the PR is merged, you are ready to publish the new patch chart version. There is a `make publish` target that runs the necessary `helm` commands to package and index the new chart. Making sure you are on the release branch, run `make publish`. This will push a commit to the `gh-pages` branch with the new chart tar file and the updated index.yaml. Double check this has been done properly by checking out the `gh-pages` branch, and that no other charts have been modified or deleted. It is expected to see timestamp changes across the yaml file as it is re-indexed.

If for any reason the publish results in a bad commit, you can revert the commit by getting the SHA of the previous commit on `gh-pages` prior to the latest push and running:
```bash
git reset --hard <SHA>
git push --force origin/gh-pages
```

**Note**: If you have forked m/charts, it may be helpful to run through these steps on your fork first to double check that the process works as expected, for peace of mind and to lower the risk of something going wrong in our charts repo.

Once the patched chart version is published, you can open up a PR in `kubeaddons-kommander` to bump the addon revision and pull in the patch. There are docs on how to patch the addon in the `kubeaddons-kommander` repo's [`README`](https://github.com/mesosphere/kubeaddons-kommander#dealing-with-previously-released-stable-versions).
