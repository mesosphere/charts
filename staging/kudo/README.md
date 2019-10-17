# KUDO

[KUDO](https://kudo.dev/) is a Kubernetes Universal Declarative Operator.

## Introduction

KUDO is currently under heavy development and requires a `kudo-system` namespace which is created when KUDO is installed with helm.

## Prerequisites

- Kubernetes 1.16+ based on CRD v1 release


## Installing the Chart

```bash
$ helm install --name kudo  ./kudo
```

Installing with a new controller version:

```bash
$ helm install --name kudo  ./kudo --set image.tag=v0.7.3
```

Installing in a cluster which already has the CRDs.

```bash
$ helm install --name kudo  ./kudo --set installCRD=false
```


## Uninstalling the Chart

```bash
$ helm delete kudo
$ helm del --purge kudo
```
