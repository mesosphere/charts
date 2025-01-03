## COSI Bucket Kit Helm Chart

This is a utility helm chart that has an implicit dependency against cosi CRDs and
can be deployed multiple times.

Facilitates the creation and management of multiple COSI resources, including:

- zero or more BucketClass resources
- zero or more BucketAccessClass resources
- zero or more BucketClaim resources
- zero or more BucketAccess resources
- an optional ceph COSI driver

### Features
- Seamless deployment of multiple bucket-related resources.
- Customizable parameters for fine-grained control over resource creation.

### Prerequisites
- Kubernetes 1.23+
- Helm 3.0+
- A deployed COSI controller and relevant COSI driver prerequisites if enabled.

### Installation

```bash
helm repo add mesosphere-stable https://mesosphere.github.io/charts/stable
helm repo update
helm install cosi-buckets mesosphere-stable/cosi-bucket-kit -f values.yaml
```
