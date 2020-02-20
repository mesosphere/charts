# cert-manager-setup

cert-manager-setup installs [cert-manager](https://github.com/jetstack/cert-manager/blob/master/deploy/charts/cert-manager/README.md) which is a Kubernetes addon to automate the management and issuance of
TLS certificates from various issuing sources.

`cert-manager` will ensure certificates are valid and up to date periodically, and attempt
to renew certificates at an appropriate time before expiry.

`cert-manager-setup` deploys the cert-manager

In addition to installing `cert-manager`, `cert-manager-setup` provides the capability to specify a `ClusterIssuer` in the `values.yaml` file which will be applied directly after the `cert-manager` installation has completed. In order for this to happen, `cert-manager-setup` sets up an `Issuer` in the `cert-manager` namespace. It then creates an intermediate certificate from the secret `kubernetes-root-ca` which must already contain ideally the Kubernetes root CA. The `ClusterIssuer` then uses the intermediate certificate derived from the Kubernetes root CA.

# Supported values format

```yaml
clusterissuer:
  name: clusterissuer-name
  spec:
    ca:
      secretName: clusterissuer-secret
```

In the given example we create a `ClusterIssuer` named `clusterissuer-name` with the `ca` type. The `ca` type expects a secret that contains the Certificate Authority (CA) to be used by this `ClusterIssuer`. The spec follows the original `cert-manager` [spec](https://docs.cert-manager.io/en/latest/tasks/issuers/setup-ca.html#creating-an-issuer-referencing-the-secret).

# Notes

In order to submit the `ClusterIssuer` post installation, `cert-manager-setup` runs a post-install `Job` hook. In case that the hook fails the Job will not be cleaned up by Helm. This behavior is intended to ease debugging.

# Upgrading from an earlier version

Read, understand and execute
1. https://cert-manager.io/docs/installation/upgrading/upgrading-0.10-0.11/
2. https://cert-manager.io/docs/installation/upgrading/upgrading-0.11-0.12/
