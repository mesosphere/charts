#!/usr/bin/env bash

# The old CRD didn't have the alertmanagerConfigNamespaceSelector field. Defining
# this causes the chart to create the unused entry which causes a validation failure.
# Removing this avoids this problem for now.

# shellcheck disable=SC1090
source "$(dirname "$0")/helpers.sh"

set -xeuo pipefail

mkdir -p "${BASEDIR}/files"

cat "${BASEDIR}"/crds/*.yaml > "${BASEDIR}/files/crds.yaml"
cat <<EOF > "${BASEDIR}/templates/install_crds.yaml"
{{ if not (.Capabilities.APIVersions.Has "prometheus.monitoring.coreos.com/v1") }}
---
{{ .Files.Get "files/crds.yaml" }}
{{ end }}
---
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: {{ .Release.Namespace }}
  name: prometheus-operator-crds
  annotations:
    "helm.sh/hook": pre-install, pre-upgrade
    "helm.sh/hook-weight": "-5"
    "helm.sh/hook-delete-policy": hook-succeeded,before-hook-creation
data:
  crds.yaml: {{ .Files.Get "files/crds.yaml" | toYaml | nindent 4 }}
---
apiVersion: batch/v1
kind: Job
metadata:
  namespace: {{ .Release.Namespace }}
  name: prometheus-operator-crds
  annotations:
    "helm.sh/hook": pre-install, pre-upgrade
    "helm.sh/hook-weight": "-4"
    "helm.sh/hook-delete-policy": hook-succeeded,before-hook-creation
spec:
  template:
    spec:
      serviceAccountName: prometheus-operator-crds
      containers:
        - name: prometheus-operator-crds
          image: "bitnami/kubectl:1.19.7"
          volumeMounts:
            - name: prometheus-operator-crds
              mountPath: /etc/prometheus-operator-crds
              readOnly: true
          command: ["kubectl", "apply", "-f", "/etc/prometheus-operator-crds"]
      volumes:
        - name: prometheus-operator-crds
          configMap:
            name: prometheus-operator-crds
      restartPolicy: OnFailure
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prometheus-operator-crds
  annotations:
    "helm.sh/hook": pre-install, pre-upgrade
    "helm.sh/hook-weight": "-5"
    "helm.sh/hook-delete-policy": hook-succeeded,before-hook-creation
rules:
  - apiGroups: ["apiextensions.k8s.io"]
    resources: ["customresourcedefinitions"]
    verbs: ["create", "get", "list", "watch", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: prometheus-operator-crds
  annotations:
    "helm.sh/hook": pre-install, pre-upgrade
    "helm.sh/hook-weight": "-5"
    "helm.sh/hook-delete-policy": hook-succeeded,before-hook-creation
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: prometheus-operator-crds
subjects:
  - kind: ServiceAccount
    name: prometheus-operator-crds
    namespace: {{ .Release.Namespace }}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: prometheus-operator-crds
  namespace: {{ .Release.Namespace }}
  annotations:
    "helm.sh/hook": pre-install, pre-upgrade
    "helm.sh/hook-weight": "-5"
    "helm.sh/hook-delete-policy": hook-succeeded,before-hook-creation
EOF

git_add_and_commit "${BASEDIR}"
