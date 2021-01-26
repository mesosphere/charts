# Gatekeeper

[Gatekeeper](https://github.com/open-policy-agent/gatekeeper/), the Policy Controller for
Kubernetes.

## Prerequisites

- Kubernetes 1.14 (or newer) for validating and mutating webhook admission
  controller support.

## Overview

This helm chart installs Gatekeeper as a [Kubernetes admission
controller](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/).
Gatekeeper is a validating (mutating TBA) webhook that enforces CRD-based policies executed by [Open
Policy Agent](https://github.com/open-policy-agent/opa), a policy engine for Cloud Native
environments hosted by [CNCF](https://www.cncf.io) as an incubation-level project.

## Kick the tires

If you just want to see something run, install the chart without any
configuration.

```bash
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts
helm install gatekeeper/gatekeeper --generate-name
```

You can then follow the instructions
[here](https://github.com/open-policy-agent/gatekeeper/#how-to-use-gatekeeper) to learn how to use
Gatekeeper.

## Configuration

All configuration settings are contained and described in
[values.yaml](values.yaml).

| Parameter                                             | Description                                                                  | Default     |
| ----------------------------------------------------- | ---------------------------------------------------------------------------- | ---------------------------------------------- |
| port                                                  | Port for gateekeper pod to listen on                                         | 8443                                           |
| service.annotations                                   | Service annotations                                                          |                                                |
| service.type                                          | Service type                                                                 | "ClusterIP"                                    |
| service.port                                          | Service port                                                                 | 443                                            |
| admissionControllerFailurePolicy                      | Admission controller failure policy                                          | "Ignore"                                       |
| admissionControllerNamespaceSelector.matchExpressions | Admission controller namespace selector expressions                          | []                                             |
| admissionControllerObjectSelector.matchExpressions    | Admission controller object selector expressions                             | []                                             |
| admissionControllerObjectSelector.matchLabels         | Admission controller object label selector                                   | []                                             |
| webhook.certManager.enabled                           | Set up the webhook certificates using cert-manager                           | false                                          |
| auditInterval                                         | The frequency with which audit is run                                        | `60`                                           |
| constraintViolationsLimit                             | The maximum # of audit violations reported on a constraint                   | `20`                                           |
| auditFromCache                                        | Take the roster of resources to audit from the OPA cache                     | `false`                                        |
| auditChunkSize                                        | Chunk size for listing cluster resources for audit (alpha feature)           | `0`                                            |
| disableValidatingWebhook                              | Disable ValidatingWebhook                                                    | `false`                                        |
| emitAdmissionEvents                                   | Emit K8s events in gatekeeper namespace for admission violations (alpha feature) | `false`                                    |
| emitAuditEvents                                       | Emit K8s events in gatekeeper namespace for audit violations (alpha feature) | `false`                                        |
| logLevel                                              | Minimum log level                                                            | `INFO`                                         |
| image.pullPolicy                                      | The image pull policy                                                        | `IfNotPresent`                                 |
| image.repository                                      | Image repository                                                             | `openpolicyagent/gatekeeper`                   |
| image.release                                         | The image release tag to use                                                 | version                                        |
| image.pullSecrets                                     | Specify an array of imagePullSecrets                                         | `[]`                                           |
| audit.resources                                       | The resource request/limits for the container image                          | limits: 1 CPU, 512Mi, requests: 100mCPU, 256Mi |
| controllerManager.resources                           | The resource request/limits for the container image                          | limits: 1 CPU, 512Mi, requests: 100mCPU, 256Mi |
| nodeSelector                                          | The node selector to use for pod scheduling                                  | `kubernetes.io/os: linux`                      |
| affinity                                              | The node affinity to use for pod scheduling                                  | `{}`                                           |
| tolerations                                           | The tolerations to use for pod scheduling                                    | `[]`                                           |
| replicas                                              | The number of Gatekeeper replicas to deploy for the webhook                  | `1`                                            |
| podAnnotations                                        | The annotations to add to the Gatekeeper pods                                | `container.seccomp.security.alpha.kubernetes.io/manager: runtime/default` |
