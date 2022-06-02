# Helm Charts

Use this repository to submit Mesosphere-owned Charts for Helm. Charts are curated application definitions for Helm. For more information about installing and using Helm, see its
[README.md](https://github.com/helm/helm/tree/master/README.md). To get a quick introduction to Charts see this [chart document](https://helm.sh/docs/topics/charts/).

## Where to find us

For general Helm Chart discussions join the Konvoy (#kubernetes) room in [Slack](https://mesosphere.slack.com/).

For issues and support for Helm and Charts see [Support Channels](CONTRIBUTING.md#support-channels).

## How do I install these charts

To add these charts for your local client, run `helm repo add`:

```bash
$ helm repo add mesosphere-staging https://mesosphere.github.io/charts/staging
"mesosphere-staging" has been added to your repositories
```

You can then run `helm search repo mesosphere-staging` to see the charts.

## Chart Format

Take a look at the [alpine example chart](https://github.com/helm/helm/tree/master/docs/examples/alpine) and the [nginx example chart](https://github.com/helm/helm/tree/master/docs/examples/nginx) for reference when you're writing your first few charts.

Before contributing a Chart, become familiar with the format. Note that the upstream project is still under active development and the format may still evolve a bit.

## Repository Structure

This GitHub repository contains the source for the packaged and versioned charts released in the [mesosphere-stable](https://mesosphere.github.io/charts/stable) and [mesosphere-staging](https://mesosphere.github.io/charts/staging) repos.

The Charts in the `stable/` directory in the master branch of this repository match the latest packaged Chart in the Chart Repository, though there may be previous versions of a Chart available in that Chart Repository.

The purpose of this repository is to provide a place for maintaining and contributing official Charts, with CI processes in place for managing the releasing of Charts into the Chart Repository.

The Charts in this repository are organized into two folders:

* stable
* staging

Stable Charts meet the criteria in the [technical requirements](CONTRIBUTING.md#technical-requirements).

Staging Charts are those that have pending contributions [upstream](https://artifacthub.io/) that are not yet merged. Having the staging folder allows charts to be hosted and used until a PR is accepted upstream. A chart PR into the `staging` repository will not be accepted without an accompanying upstream pull request.

## Contributing a Chart

We'd love for you to contribute a Chart. Please consider contributing upstream first. Please read our [Contribution Guide](CONTRIBUTING.md) for more information on how you can contribute Charts.

Note: We use the same [workflow](https://github.com/kubernetes/community/blob/master/contributors/devel/development.md#workflow).

## Testing

For instructions on testing chart changes, see [TESTING.md](./TESTING.md)

## Review Process

For information related to the review procedure used by the Chart repository maintainers, see [Merge approval and release process](CONTRIBUTING.md#merge-approval-and-release-process).

### Stale Pull Requests and Issues

Pull Requests and Issues that have no activity for 30 days automatically become stale. After 30 days of being stale, without activity, they become rotten. Pull Requests and Issues can rot for 30 days and then they are automatically closed. This is the standard stale process handling for all repositories on the Kubernetes GitHub organization, a standard which we will follow.

## Supported Kubernetes Versions

This chart repository supports the latest and previous two minor versions of Kubernetes. For example, if the latest minor release of Kubernetes is 1.15 than 1.13, 1.14, and 1.15 are supported. Charts may still work on previous versions of Kubernertes even though they are outside the target supported window.

To provide that support the Kubernetes API versions of objects should be those that work for all supported releases.

## Status of the Project

By it's very nature, this project is still under active development, so you might run into [issues](https://github.com/mesosphere/charts/issues). If you do, please don't be shy about letting us know, or better yet, contribute a fix or feature.
