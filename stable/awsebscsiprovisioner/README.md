# AWS EBS CSI Provisioner

**NOTE:** We recommend that this chart always be released to the `kube-system` namespace for it to function correctly 

## introduction
This chart providers the deployment of the `AWS EBS CSI Driver` while at the same time creating a proper storage class which could be defaulted as needed.