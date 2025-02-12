# harbor-copy-secret

A helm chart that copies secret content between namespaces, can be useful when a secret is created in a
workspace namespace and needs to be copied to a release namespace.

## How it works

Chart can be activated by enabling the `enabled` flag, it will then copy the secret content from the source namespace to the target namespace.

```yaml
harborCopySecret:
  enabled: true
  sourceSecretName: "secret"
  targetNamespace: "release"
  targetSecretName: "secret" # by default it will use the source secret name
  reloader: true
```
