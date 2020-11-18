# Kommander
Represents an umbrella chart for deploying multiple charts:
- Kommander-Karma
- Kommander-Thanos
- Grafana
- Kommander-Cluster-Lifecycle
- Kommander-ui
- Kubeaddons-Catalog

## Pre-Reqs for Installation
You must have `Cert-Manager` installed in your cluster.

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
