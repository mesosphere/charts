# Nvidia

[Nvidia Device Plugin](https://github.com/NVIDIA/k8s-device-plugin) allows GPUs on each node to be exposed to the kubernetes cluster. It
also supports checking the health of GPUs, and runs GPU enabled containers in the cluster.

## Introduction

This chart bootstraps the Nvidia Device Plugin on Nvidia GPU enabled nodes.

## Prerequisites

### Nvidia Device Plugin

1. NVIDIA drivers ~= 384.81
2. nvidia-docker version > 2.0 (see how to [install](https://github.com/NVIDIA/nvidia-docker) and it's [prerequisites](https://github.com/nvidia/nvidia-docker/wiki/Installation-(version-2.0)#prerequisites))
3. docker configured with nvidia as the [default runtime](https://github.com/NVIDIA/nvidia-docker/wiki/Advanced-topics#default-runtime).
4. Kubernetes version >= 1.10

## Installing the Chart

```bash
$ helm install staging/nvidia --name nvidia
```

## Uninstalling the Chart

```bash
$ helm delete nvidia
```

