# Nvidia

[Nvidia Driver Container](https://github.com/NVIDIA/nvidia-docker/wiki/Driver-containers-(Beta) allows the provisioning of Nvidia driver through
the use of containers. It simplifies the deployment and installation of the Nvidia driver, and makes it easier for reproducibility and upgrade case.

[Nvidia Device Plugin](https://github.com/NVIDIA/k8s-device-plugin) allows GPUs on each node to be exposed to the kubernetes cluster. It
also supports checking the health of GPUs, and runs GPU enabled containers in the cluster.

## Introduction

This chart bootstraps the Nvidia Driver and Nvidia Device Plugin on Nvidia GPU enabled nodes.

## Prerequisites

### Nvidia Driver Containers

1. Ubuntu 16.04, Ubuntu 18.04 or Centos 7 with the IPMI driver enabled and the Nouveau driver disabled
2. NVIDIA GPU with Architecture > Fermi (2.1)
3. A [supported version of Docker](https://github.com/NVIDIA/nvidia-docker/wiki/Frequently-Asked-Questions#which-docker-packages-are-supported)
4. The [NVIDIA Container Runtime for Docker](https://github.com/NVIDIA/nvidia-docker/wiki/Installation-(version-2.0)) configured with the root option
5. If you are running Ubuntu 18.04 with an AWS kernel, you also need to enable the i2c_core kernel module

### Nvidia Device Plugin

1. NVIDIA drivers ~= 361.93
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
