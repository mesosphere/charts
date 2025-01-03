## README.md

# COSI Bucket Collection Helm Chart

This Helm chart facilitates the creation and management of multiple COSI resources, including:

- **BucketClass**
- **BucketAccessClass**
- **BucketClaim** (multiple)
- **BucketAccess** (multiple)

### Features
- Seamless deployment of multiple bucket-related resources.
- Customizable parameters for fine-grained control over resource creation.

### Prerequisites
- Kubernetes 1.23+
- Helm 3.0+
- A deployed COSI driver compatible with your storage backend.

### Installation

```bash
helm repo add mesosphere-stable https://mesosphere.github.io/charts/stable
helm repo update
helm install cosi-buckets mesosphere-stable/cosi-bucket-kit
```
