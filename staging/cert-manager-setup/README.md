# cert-manager-setup

cert-manager-setup installs [cert-manager](https://github.com/jetstack/cert-manager/blob/master/deploy/charts/cert-manager/README.md) which is a Kubernetes addon to automate the management and issuance of
TLS certificates from various issuing sources

It will ensure certificates are valid and up to date periodically, and attempt
to renew certificates at an appropriate time before expiry.

In addition to installing cert-manager, cert-manager-setup provides the capability to specify `ClusterIssuers` in the `values.yaml` file which will be applied directly after the `cert-manager` installation has completed.

# notes

In order to submit the `ClusterIssuers` post installation, `cert-manager-setup` runs a post-install `Job` hook. In case that the hook fails the Job will not be cleaned up by Helm. This behavior is intended to ease debugging.
