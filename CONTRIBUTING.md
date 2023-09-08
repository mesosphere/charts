# Contributing Guidelines

The Kubernetes Charts project accepts contributions via GitHub pull requests. This document outlines the process to help get your contribution accepted.

## Reporting a Bug in Helm

This repository is used by Mesosphere developers for maintaining charts for Kubernetes Helm. If your issue is in the Helm tool itself, please use the issue tracker in the [helm/helm](https://github.com/helm/helm) repository.

## How to Contribute a Chart

1. Create a branch using your github username, a slash, and a topic (ie. `joegithub/my_own_chart`), develop and test your Chart.
1. Choose the correct folder for your chart based on the information in the [Repository Structure](README.md#repository-structure) section
1. Ensure your Chart follows the [technical](#technical-requirements) and [documentation](#documentation-requirements) guidelines, described below.
1. Submit a pull request.

***NOTE***: In order to make testing and merging of PRs easier, please submit changes to multiple charts in separate PRs.

If you need [initContainer](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/) or [job](https://kubernetes.io/docs/concepts/workloads/controllers/jobs-run-to-completion/) support in your chart and need to create new functionality for this (e.g. there's not an existing docker image that would support your needs) see our [Kubeaddons ExtraSteps](https://github.com/mesosphere/kubeaddons-extrasteps) repository which contains custom functionality for these purposes.

### Technical requirements

* All Chart dependencies should also be submitted independently
* Must pass the linter (`helm lint`)
* Must successfully launch with default values (`helm install .`)
  * All pods go to the running state (or NOTES.txt provides further instructions if a required value is missing e.g. [minecraft](https://github.com/helm/charts/blob/master/stable/minecraft/templates/NOTES.txt#L3))
  * All services have at least one endpoint
* Must include source GitHub repositories for images used in the Chart
* Images should not have any major security vulnerabilities
* Must be up-to-date with the latest stable Helm/Kubernetes features
* Should follow Kubernetes best practices
  * Include Health Checks wherever practical
  * Allow configurable [resource requests and limits](http://kubernetes.io/docs/user-guide/compute-resources/#resource-requests-and-limits-of-pod-and-container)
* Provide a method for data persistence (if applicable)
* Support application upgrades
* Allow customization of the application configuration
* Provide a secure default configuration
* Do not leverage alpha features of Kubernetes
* Includes a [NOTES.txt](https://github.com/helm/helm/blob/master/docs/charts.md#chart-license-readme-and-notes) explaining how to use the application after install
* Follows [best practices](https://github.com/helm/helm/tree/master/docs/chart_best_practices)
  (especially for [labels](https://github.com/helm/helm/blob/master/docs/chart_best_practices/labels.md)
  and [values](https://github.com/helm/helm/blob/master/docs/chart_best_practices/values.md))

### Documentation requirements

* Must include an in-depth `README.md`, including:
  * Short description of the Chart
  * Any prerequisites or requirements
  * Customization: explaining options in `values.yaml` and their defaults
    * Optionally values may be documented directly in the `values.yaml`
* Must include a short `NOTES.txt`, including:
  * Any relevant post-installation information for the Chart
  * Instructions on how to access the application or service provided by the Chart

### Merge approval and release process

A Kubernetes Charts maintainer will review the Chart submission, and start a validation job in the CI to verify the technical requirements of the Chart. A maintainer may add "LGTM" (Looks Good To Me) or an equivalent comment to indicate that a PR is acceptable. Any change requires at least one LGTM. No pull requests can be merged until at least one maintainer signs off with an LGTM.

Once the Chart has been merged, the release job will automatically run in the CI to package and release the Chart.

### Releasing patch versions of charts

In some instances, we must release patches to previously released/published helm charts.
For example, if there is a fix we must make to a chart that was released in a previous version of DKP, for which there is already a newer release of the chart on the `main` branch.

Follow this process to create patch releases for a helm chart:
* Check out the SHA at which the chart was at the version in which you need to patch
* Create a new release branch from this branch, with the format `release/helm-chart-name-N.N.x` e.g. `release/kube-prometheus-stack-46.8.x`
* Push the branch (this will be a protected branch)
* Open a PR against this release branch with your fixes, ensuring that you bump the helm chart patch version
* Once the PR merges, the publish workflow is triggered (on pushes to `release/*` branches)

## Support Channels

Whether you are a user or contributor, official support channels include:

* GitHub issues: [https://github.com/mesosphere/charts/issues](https://github.com/mesosphere/charts/issues)
* Slack: #eng-konvoy room

Before opening a new issue or submitting a new pull request, it's helpful to search the project - it's likely that another user has already reported the issue you're facing, or it's a known issue that we're already aware of.
